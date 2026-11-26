-- name: Fuga de Radiacao
-- desc: Desvie o vazamento do reator para os tanques de contencao
-- ver: 1.2
-- LIMITES: jogo de ficcao (liquido verde ficticio). So texto/ASCII, sem som, imagens ou rede.
-- Recorde salvo com nitro.cfg.

return function(args)
  local gpu, nitro = args.gpu, args.nitro
  local C = nitro.colors
  local W, H = 40, 16
  local RROW = math.floor(H / 2)

  local T_EMPTY, T_WALL, T_PIPE_H, T_PIPE_V = ".", "#", "=", "|"
  local T_VALVE, T_TANK, T_REACTOR, T_LEAK = "+", "T", "R", "~"

  local STEP_TIME = 0.6          -- segundos entre passos do vazamento
  local MAX_LEAKS = 8            -- teto de vazamentos ativos
  local TRAIL_LIFE = 4           -- passos ate o rastro sumir
  local DAMAGE_PER_HIT = 10
  local MAX_DAMAGE = 100

  -- recorde: usa nitro.cfg se existir (versoes antigas do sistema nao tem)
  local function loadBest()
    if type(nitro.cfg) ~= "table" or type(nitro.cfg.load) ~= "function" then return 0 end
    local ok, data = pcall(nitro.cfg.load, "recorde")
    if ok and type(data) == "table" and type(data.melhor) == "number" then
      return math.floor(data.melhor)
    end
    return 0
  end

  local function saveBest(val)
    if type(nitro.cfg) ~= "table" or type(nitro.cfg.save) ~= "function" then return end
    pcall(nitro.cfg.save, "recorde", { melhor = math.floor(val) })
  end

  -- grade: tabela de linhas; trail: posicoes com tempo de vida (rastro)
  local function newGrid(level, tanks)
    local grid = {}
    for y = 1, H do
      grid[y] = {}
      for x = 1, W do
        if y == 1 or y == H or x == 1 or x == W then
          grid[y][x] = T_WALL
        else
          grid[y][x] = T_EMPTY
        end
      end
    end
    grid[RROW][2] = T_REACTOR
    grid[RROW][3] = T_PIPE_H
    grid[RROW][4] = T_PIPE_H
    grid[RROW][5] = T_VALVE
    for _, ty in ipairs({ 4, 8, 12 }) do
      grid[ty][W - 1] = T_TANK
      grid[ty][W - 2] = T_PIPE_H
      grid[ty][W - 3] = T_VALVE
    end
    for x = 6, W - 5 do
      if x % 4 == 0 then grid[RROW][x] = T_PIPE_H end
    end
    for y = 3, H - 2 do
      if y % 4 == 0 and y ~= RROW then
        grid[y][10] = T_PIPE_V
        grid[y][22] = T_PIPE_V
      end
    end
    -- paredes extras conforme o nivel (sequencia deterministica)
    local extra = math.min(18, 3 + level * 3 + tanks)
    local seed = level * 997 + tanks * 131 + 17
    local placed, guard = 0, 0
    while placed < extra and guard < 250 do
      guard = guard + 1
      seed = (seed * 1103515245 + 12345) % 2147483648
      local wx = 6 + (seed % (W - 9))
      seed = (seed * 1103515245 + 12345) % 2147483648
      local wy = 2 + (seed % (H - 3))
      local nearReactor = (wx <= 6 and math.abs(wy - RROW) <= 1)
      local nearTank = (wx >= W - 4)
      if not nearReactor and not nearTank and grid[wy][wx] == T_EMPTY then
        grid[wy][wx] = T_WALL
        placed = placed + 1
      end
    end
    return grid
  end

  local function initState(best)
    local grid = newGrid(1, 0)
    return {
      grid = grid,
      leaks = { { x = 3, y = RROW, dx = 1, dy = 0, life = 0 } },
      trail = {},            -- trail[y*W+x] = passos restantes
      cx = 7, cy = RROW,
      score = 0, best = best,
      damage = 0, tanksFilled = 0, level = 1,
      elapsed = 0, stepAccum = 0, stepInterval = STEP_TIME,
      status = "Setas: mover | Espaco: valvula | Esc: sair",
      gameOver = false, dirty = true,
      delayNewLeak = 0,
    }
  end

  local function hurt(state, msg)
    state.damage = math.min(MAX_DAMAGE, state.damage + DAMAGE_PER_HIT)
    state.status = msg
  end

  local function touchTrail(state, x, y)
    state.trail[y * W + x] = TRAIL_LIFE
  end

  -- um passo do vazamento: cada vazamento anda 1 celula
  local function stepLeaks(state)
    local grid = state.grid
    local nextLeaks = {}
    for _, lk in ipairs(state.leaks) do
      local nx, ny = lk.x + lk.dx, lk.y + lk.dy
      if nx < 2 or nx > W - 1 or ny < 2 or ny > H - 1 then
        hurt(state, "Vazamento na borda!")
      else
        local cell = grid[ny][nx]
        if cell == T_WALL then
          hurt(state, "Bateu na parede!")
        elseif cell == T_TANK then
          state.score = state.score + 50
          state.tanksFilled = state.tanksFilled + 1
          grid[ny][nx] = T_WALL
          state.status = "Tanque cheio! +50 pts"
          if state.tanksFilled % 3 == 0 then
            state.level = state.level + 1
            state.stepInterval = math.max(0.22, state.stepInterval - 0.08)
            state.grid = newGrid(state.level, state.tanksFilled)
            state.leaks, state.trail = {}, {}
            state.status = "Nivel " .. state.level .. "! Mais rapido"
            return
          end
        elseif cell == T_VALVE then
          local branched = false
          local dirs = { { 0, -1 }, { 0, 1 }, { lk.dx, lk.dy } }
          for _, d in ipairs(dirs) do
            local tx, ty = nx + d[1], ny + d[2]
            if tx >= 2 and tx <= W - 1 and ty >= 2 and ty <= H - 1 then
              local t = grid[ty][tx]
              if t ~= T_WALL and t ~= T_REACTOR and not branched and #nextLeaks < MAX_LEAKS then
                nextLeaks[#nextLeaks + 1] = { x = nx, y = ny, dx = d[1], dy = d[2], life = 0 }
                branched = true
              end
            end
          end
          if not branched then hurt(state, "Valvula bloqueada!") end
        elseif cell == T_PIPE_H and lk.dy ~= 0 then
          hurt(state, "Cano horizontal fechado!")
        elseif cell == T_PIPE_V and lk.dx ~= 0 then
          hurt(state, "Cano vertical fechado!")
        else
          -- vazio ou cano na direcao certa: o vazamento segue
          if cell == T_EMPTY or cell == T_PIPE_H or cell == T_PIPE_V then
            if #nextLeaks < MAX_LEAKS then
              nextLeaks[#nextLeaks + 1] = { x = nx, y = ny, dx = lk.dx, dy = lk.dy, life = 0 }
            end
          end
        end
        if cell == T_EMPTY or cell == T_PIPE_H or cell == T_PIPE_V or cell == T_VALVE then
          touchTrail(state, nx, ny)
        end
      end
    end
    state.leaks = nextLeaks

    -- sem vazamento ativo: cria um novo no reator, com intervalo (sem dano duplicado)
    if #state.leaks == 0 and state.damage < MAX_DAMAGE then
      if state.delayNewLeak <= 0 then
        state.leaks[1] = { x = 3, y = RROW, dx = 1, dy = 0, life = 0 }
        state.delayNewLeak = 2
      else
        state.delayNewLeak = state.delayNewLeak - 1
      end
    end
  end

  -- apaga o rastro com o tempo (passos)
  local function ageTrail(state)
    for k, life in pairs(state.trail) do
      if life <= 1 then
        state.trail[k] = nil
      else
        state.trail[k] = life - 1
      end
    end
  end

  local function fullDraw(state)
    local sw, sh = gpu.getResolution()
    gpu.setBackground(C.bg)
    gpu.setForeground(C.text)
    gpu.fill(1, 1, sw, sh, " ")
    local ox = math.max(1, math.floor((sw - W) / 2) + 1)
    local oy = math.max(2, math.floor((sh - H) / 2))
    gpu.setForeground(C.accent)
    local top = string.format("FUGA DE RADIACAO | Nv:%d | Tanques:%d | Rec:%d",
      state.level, state.tanksFilled, state.best)
    gpu.set(ox, math.max(1, oy - 1), top:sub(1, sw))
    state.oxf, state.oyf = ox, oy
    for y = 1, H do
      for x = 1, W do
        local ch = state.grid[y][x]
        local k = y * W + x
        if state.trail[k] and (ch == T_EMPTY or ch == T_PIPE_H or ch == T_PIPE_V) then
          ch = T_LEAK
        end
        local isLeak = false
        for _, lk in ipairs(state.leaks) do
          if lk.x == x and lk.y == y then isLeak = true break end
        end
        if isLeak then ch = T_LEAK end
        gpu.setBackground(C.bg)
        gpu.setForeground(C.text)
        if ch == T_LEAK then gpu.setForeground(C.ok)
        elseif ch == T_REACTOR then gpu.setForeground(C.warn)
        elseif ch == T_TANK then gpu.setForeground(C.accent)
        elseif ch == T_WALL then gpu.setForeground(C.dim)
        elseif ch == T_VALVE then gpu.setForeground(C.warn) end
        if x == state.cx and y == state.cy then
          gpu.setBackground(C.accent)
          gpu.setForeground(C.bg)
        end
        gpu.set(ox + x - 1, oy + y - 1, ch)
      end
    end
    gpu.setBackground(C.bg)
    state.dirty = false
  end

  local function drawBar(state)
    local sw, sh = gpu.getResolution()
    local barY = math.min(sh, (state.oyf or 2) + H)
    gpu.setBackground(C.panel)
    gpu.setForeground(C.text)
    gpu.fill(1, barY, sw, 1, " ")
    local info = string.format("Pts:%d | Tempo:%.1fs | ", state.score, state.elapsed)
    gpu.set(1, barY, info)
    local dmgColor = (state.damage >= 70 and C.err) or (state.damage >= 40 and C.warn) or C.ok
    local dmg = string.format("Dano:%d%%", state.damage)
    gpu.setForeground(dmgColor)
    gpu.set(1 + #info, barY, dmg)
    gpu.setForeground(C.dim)
    local pos = 1 + #info + #dmg + 2
    if pos < sw then gpu.set(pos, barY, ("[" .. state.status .. "]"):sub(1, sw - pos + 1)) end
    gpu.setBackground(C.bg)
  end

  local function gameOverBox(state)
    local sw, sh = gpu.getResolution()
    local bw, bh = math.min(36, sw - 4), 7
    local bx = math.max(1, math.floor((sw - bw) / 2) + 1)
    local by = math.max(1, math.floor((sh - bh) / 2) + 1)
    gpu.setBackground(C.panel)
    gpu.fill(bx, by, bw, bh, " ")
    gpu.setForeground(C.err)
    gpu.set(bx + 2, by + 1, "Fim de jogo")
    gpu.setForeground(C.text)
    gpu.set(bx + 2, by + 2, ("Pontuacao: " .. state.score .. " (Rec: " .. state.best .. ")"):sub(1, bw - 4))
    gpu.setForeground(C.ok)
    gpu.set(bx + 2, by + 4, "Enter: jogar de novo")
    gpu.setForeground(C.dim)
    gpu.set(bx + 2, by + 5, "Esc: sair")
    gpu.setBackground(C.bg)
  end

  local function handleKey(state, ch, code)
    if state.gameOver then
      if code == 28 then
        local best = state.best
        return initState(best)
      end
      return state
    end
    if code == 200 and state.cy > 2 then state.cy = state.cy - 1; state.dirty = true
    elseif code == 208 and state.cy < H - 1 then state.cy = state.cy + 1; state.dirty = true
    elseif code == 203 and state.cx > 2 then state.cx = state.cx - 1; state.dirty = true
    elseif code == 205 and state.cx < W - 1 then state.cx = state.cx + 1; state.dirty = true
    elseif ch == 32 then
      local cur = state.grid[state.cy][state.cx]
      if cur == T_EMPTY then
        state.grid[state.cy][state.cx] = T_VALVE
        state.status = "Valvula colocada"
      elseif cur == T_VALVE then
        state.grid[state.cy][state.cx] = T_EMPTY
        state.status = "Valvula removida"
      else
        state.status = "Celula ocupada"
      end
      state.dirty = true
    end
    return state
  end

  local best = loadBest()
  local state = initState(best)
  fullDraw(state)
  drawBar(state)

  local lastTick = nil
  local ticks = 0
  while true do
    local ev, _, ch, code = nitro.pull(0.1)
    -- so conta tempo quando o pull expirou sem evento (tecla nao acelera o jogo)
    local dt = (ev == nil) and 0.1 or 0
    if ev == "key_down" then
      if code == 1 then
        if state.score > state.best then
          state.best = state.score
          saveBest(state.best)
        end
        return
      end
      state = handleKey(state, ch, code)
    end

    if not state.gameOver then
      -- tempo medido pelo intervalo real (nao pelo numero de teclas apertadas)
      ticks = ticks + 1
      state.elapsed = state.elapsed + dt
      state.stepAccum = state.stepAccum + dt
      while state.stepAccum >= state.stepInterval and not state.gameOver do
        state.stepAccum = state.stepAccum - state.stepInterval
        stepLeaks(state)
        ageTrail(state)
        state.dirty = true
        if state.damage >= MAX_DAMAGE then
          state.damage = MAX_DAMAGE
          state.gameOver = true
          if state.score > state.best then
            state.best = state.score
            saveBest(state.best)
          end
        end
      end
    end

    -- redesenha so quando algo mudou (sem piscar)
    if state.dirty or ticks % 5 == 0 then
      fullDraw(state)
      drawBar(state)
      if state.gameOver then gameOverBox(state) end
    end
  end
end
