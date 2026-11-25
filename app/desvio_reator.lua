-- Desvio no Reator (Fuga de Radiação) - Nitro OS 2D App
local CFG_NAME = "recorde"

local function now()
  if type(nitro) == "table" and type(nitro.uptime) == "function" then
    local ok, t = pcall(nitro.uptime)
    if ok and type(t) == "number" then return t end
  end
  return 0
end

local function getSize()
  local w = (type(nitro) == "table" and tonumber(nitro.width)) or 56
  local h = (type(nitro) == "table" and tonumber(nitro.height)) or 22
  if type(nitro) == "table" and type(nitro.gpu) == "table" and type(nitro.gpu.getResolution) == "function" then
    local ok, gw, gh = pcall(nitro.gpu.getResolution)
    if ok and type(gw) == "number" and type(gh) == "number" then
      w, h = gw, gh
    end
  end
  return math.max(38, math.floor(w)), math.max(15, math.floor(h))
end

local function getPalette()
  local c = (type(nitro) == "table" and type(nitro.colors)) or {}
  return {
    bg     = c.bg     or 0x090A0F,
    panel  = c.panel  or c.barbg or 0x111827,
    wall   = c.accent or 0x2563EB,
    accent = c.accent or 0x38BDF8,
    danger = c.err    or 0xEF4444,
    player = c.warn   or 0xFACC15,
    shield = c.ok     or 0x22C55E,
    text   = c.text   or 0xF8FAFC,
    muted  = c.dim    or 0x94A3B8
  }
end

local function rectBg(x, y, w, h, bg)
  if w <= 0 or h <= 0 then return end
  if type(nitro) == "table" and type(nitro.rect) == "function" then
    pcall(nitro.rect, x, y, w, h, bg)
  elseif type(nitro) == "table" and type(nitro.gpu) == "table" and type(nitro.gpu.fill) == "function" then
    if bg and type(nitro.gpu.setBackground) == "function" then pcall(nitro.gpu.setBackground, bg) end
    pcall(nitro.gpu.fill, x, y, w, h, " ")
  end
end

local function put(x, y, txt, fg, bg)
  local s = tostring(txt or "")
  if type(nitro) == "table" and type(nitro.put) == "function" then
    pcall(nitro.put, x, y, s, fg, bg)
  elseif type(nitro) == "table" and type(nitro.gpu) == "table" and type(nitro.gpu.set) == "function" then
    if bg and type(nitro.gpu.setBackground) == "function" then pcall(nitro.gpu.setBackground, bg) end
    if fg and type(nitro.gpu.setForeground) == "function" then pcall(nitro.gpu.setForeground, fg) end
    pcall(nitro.gpu.set, x, y, s)
  end
end

local function box(x, y, w, h, bg, borderFg)
  rectBg(x, y, w, h, bg)
  if w >= 2 and h >= 2 then
    put(x, y, string.rep("▀", w), borderFg, bg)
    put(x, y + h - 1, string.rep("▄", w), borderFg, bg)
    for row = y + 1, y + h - 2 do
      put(x, row, "│", borderFg, bg)
      put(x + w - 1, row, "│", borderFg, bg)
    end
  end
end

local function pull(dt)
  if type(nitro) == "table" and type(nitro.pull) == "function" then
    local ok, ev, addr, chr, code = pcall(nitro.pull, dt or 0.05)
    if ok then return ev, addr, chr, code end
  end
  return nil
end

local function loadCfg()
  local out = { recorde = 0, modo = "normal" }
  if type(nitro) == "table" and type(nitro.cfg) == "table" and type(nitro.cfg.load) == "function" then
    local ok, data = pcall(nitro.cfg.load, CFG_NAME)
    if ok and type(data) == "table" then
      out.recorde = math.max(0, math.floor(tonumber(data.recorde) or 0))
      if data.modo == "rapido" then out.modo = "rapido" end
    elseif ok and type(data) == "number" then
      out.recorde = math.max(0, math.floor(data))
    end
  end
  return out
end

local function saveCfg(cfg)
  if type(nitro) == "table" and type(nitro.cfg) == "table" and type(nitro.cfg.save) == "function" then
    pcall(nitro.cfg.save, CFG_NAME, {
      recorde = math.max(0, math.floor(tonumber(cfg.recorde) or 0)),
      modo = (cfg.modo == "rapido") and "rapido" or "normal"
    })
  end
end

local function run()
  local w, h = getSize()
  local pal = getPalette()
  local cfg = loadCfg()
  local best = cfg.recorde
  local fastMode = (cfg.modo == "rapido")

  local stars = {}
  for i = 1, 25 do
    stars[i] = { x = math.random(1, w), y = math.random(1, h), s = math.random(1, 2) }
  end
  local scroll = 0

  local lanes = 3
  local laneW = 9
  local trackW = lanes * laneW + 4
  local trackX = math.max(2, math.floor((w - trackW) / 2))
  local topY = 4
  local botY = math.max(topY + 7, h - 3)
  local playerY = botY - 1

  local state = "menu" -- "menu", "playing", "paused", "gameover"
  local menuIdx = 1 -- 1: Jogar, 2: Velocidade, 3: Sair
  local lane = 2
  local score = 0
  local shield = false
  local baseDelay = fastMode and 0.20 or 0.28
  local stepDelay = baseDelay
  local lastStep = now()
  local lastScore = now()
  local spawnCd = 0
  local obstacles = {}

  local function reset()
    baseDelay = fastMode and 0.20 or 0.28
    stepDelay = baseDelay
    lane = 2
    score = 0
    shield = false
    spawnCd = 0
    obstacles = {}
    scroll = 0
    lastStep = now()
    lastScore = now()
  end

  local function toggleSpeed()
    fastMode = not fastMode
    cfg.modo = fastMode and "rapido" or "normal"
    saveCfg(cfg)
  end

  local function laneX(l)
    return trackX + 2 + (l - 1) * laneW + math.floor(laneW / 2)
  end

  local function moveLeft()
    if lane > 1 then lane = lane - 1 end
  end

  local function moveRight()
    if lane < lanes then lane = lane + 1 end
  end

  local function render()
    rectBg(1, 1, w, h, pal.bg)

    for _, st in ipairs(stars) do
      put(st.x, st.y, st.s == 2 and "*" or ".", pal.muted, pal.bg)
    end

    rectBg(1, 1, w, 1, pal.panel)
    put(2, 1, "DESVIO NO REATOR // FUGA DE RADIACAO", pal.danger, pal.panel)

    local speed = math.floor((0.28 - stepDelay) / 0.19 * 8 + 0.5)
    speed = math.max(0, math.min(8, speed))
    local bar = string.rep("█", speed) .. string.rep("░", 8 - speed)
    put(math.max(2, w - 14), 1, "VEL " .. bar, pal.accent, pal.panel)

    put(2, 2, string.format("Pts: %-6d  Rec: %-6d  Escudo: %s",
      math.floor(score), best, shield and "ON" or "OFF"), pal.text, pal.bg)

    for y = topY, botY do
      put(trackX, y, "██", pal.wall, pal.bg)
      put(trackX + trackW - 2, y, "██", pal.wall, pal.bg)
    end
    put(trackX, topY - 1, string.rep("▀", trackW), pal.accent, pal.bg)

    for l = 1, lanes - 1 do
      local dx = trackX + 2 + l * laneW - math.floor(laneW / 2)
      for y = topY + (scroll % 2), botY, 2 do
        put(dx, y, "│", pal.muted, pal.bg)
      end
    end

    for _, ob in ipairs(obstacles) do
      local ox = laneX(ob.lane)
      if ob.y >= topY and ob.y <= botY then
        if ob.kind == "cool" then
          put(ox - 1, ob.y, "(", pal.accent, pal.bg)
          put(ox, ob.y, "O", pal.text, pal.accent)
          put(ox + 1, ob.y, ")", pal.accent, pal.bg)
        else
          local glow = (math.floor(now() * 8) % 2 == 0) and "▓▓▓" or "▒▒▒"
          put(ox - 1, ob.y, glow, pal.danger, pal.bg)
          put(ox, ob.y, "▲", pal.text, pal.danger)
        end
      end
    end

    local px = laneX(lane)
    if shield then
      local pulse = (math.floor(now() * 6) % 2 == 0) and pal.shield or pal.accent
      put(px - 2, playerY, "░", pulse, pal.bg)
      put(px + 2, playerY, "░", pulse, pal.bg)
    end
    put(px, playerY - 1, "▲", pal.player, pal.bg)
    put(px - 1, playerY, "▄█▄", pal.player, pal.bg)

    put(2, h - 1, "[<-/-> ou A/D] Mover  [P] Pausa  [Q] Sair", pal.muted, pal.bg)

    if state == "menu" then
      local bw, bh = math.min(w - 6, 40), 10
      local bx, by = math.floor((w - bw) / 2), math.floor(h / 2) - 5
      box(bx, by, bw, bh, pal.panel, pal.accent)
      put(bx + 2, by + 1, "DESVIO NO REATOR", pal.player, pal.panel)
      put(bx + 2, by + 2, string.format("Recorde: %d", best), pal.muted, pal.panel)

      local opts = {
        "Jogar",
        "Velocidade: " .. (fastMode and "Rapido" or "Normal"),
        "Sair"
      }
      for i = 1, 3 do
        local sel = (menuIdx == i)
        local fg = sel and pal.player or pal.text
        local prefix = sel and "> " or "  "
        put(bx + 2, by + 3 + i, prefix .. opts[i], fg, pal.panel)
      end
      put(bx + 2, by + 8, "[Cima/Baixo] Escolher  [Enter] OK", pal.accent, pal.panel)
    elseif state == "paused" then
      local bw, bh = 28, 3
      local bx, by = math.floor((w - bw) / 2), math.floor(h / 2) - 1
      box(bx, by, bw, bh, pal.panel, pal.player)
      put(bx + 3, by + 1, "PAUSADO - [P] continuar", pal.player, pal.panel)
    elseif state == "gameover" then
      local blinkBg = (math.floor(now() * 4) % 2 == 0) and pal.danger or pal.panel
      local blinkFg = (math.floor(now() * 4) % 2 == 0) and pal.text or pal.danger
      local bw, bh = math.min(w - 6, 38), 7
      local bx, by = math.floor((w - bw) / 2), math.floor(h / 2) - 3
      box(bx, by, bw, bh, blinkBg, blinkFg)
      put(bx + 2, by + 1, "FALHA DE CONTENCAO!", pal.text, blinkBg)
      put(bx + 2, by + 2, string.format("Pontuacao: %d (Rec: %d)", math.floor(score), best), pal.text, blinkBg)
      put(bx + 2, by + 4, "[ENTER/R] Reiniciar   [M] Menu", pal.player, blinkBg)
    end
  end

  local function step()
    local t = now()
    if t - lastScore >= 0.25 then
      lastScore = t
      score = score + 1
      if math.floor(score) % 30 == 0 and stepDelay > 0.09 then
        stepDelay = math.max(0.09, stepDelay - 0.02)
      end
    end

    if t - lastStep >= stepDelay then
      lastStep = t

      scroll = scroll + 1
      for _, st in ipairs(stars) do
        st.y = st.y + 1
        if st.y > h then
          st.y = 2
          st.x = math.random(1, w)
        end
      end

      local kept = {}
      for _, ob in ipairs(obstacles) do
        local ny = ob.y + 1
        if (ny == playerY or ny == playerY - 1) and ob.lane == lane then
          if ob.kind == "cool" then
            shield = true
            score = score + 15
          elseif shield then
            shield = false
            score = score + 10
          else
            local finalPts = math.floor(score)
            if finalPts > best then
              best = finalPts
              cfg.recorde = best
              saveCfg(cfg)
            end
            state = "gameover"
            return
          end
        elseif ny <= botY then
          ob.y = ny
          table.insert(kept, ob)
        end
      end
      obstacles = kept

      if spawnCd <= 0 then
        local l1 = math.random(1, lanes)
        local k1 = (math.random(1, 7) == 1) and "cool" or "rad"
        table.insert(obstacles, { lane = l1, y = topY, kind = k1 })
        if math.random(1, 3) == 1 then
          table.insert(obstacles, { lane = (l1 % lanes) + 1, y = topY, kind = "rad" })
        end
        spawnCd = 2
      else
        spawnCd = spawnCd - 1
      end
    end
  end

  while true do
    local ev, _, chr, code = pull(0.05)

    if ev == "key_down" then
      local ch = (type(chr) == "number" and chr > 0 and chr < 256) and string.char(chr):lower() or ""
      code = tonumber(code)

      if state == "menu" then
        if code == 200 or ch == "w" then
          menuIdx = (menuIdx == 1) and 3 or (menuIdx - 1)
        elseif code == 208 or ch == "s" then
          menuIdx = (menuIdx % 3) + 1
        elseif (code == 203 or code == 205 or ch == "a" or ch == "d") and menuIdx == 2 then
          toggleSpeed()
        elseif ch == "\r" or ch == "\n" or ch == " " or code == 28 or code == 57 then
          if menuIdx == 1 then
            reset()
            state = "playing"
          elseif menuIdx == 2 then
            toggleSpeed()
          elseif menuIdx == 3 then
            break
          end
        elseif ch == "q" or code == 16 then
          break
        end
      elseif state == "playing" then
        if ch == "q" or code == 16 then
          break
        elseif code == 203 or ch == "a" then
          moveLeft()
        elseif code == 205 or ch == "d" then
          moveRight()
        elseif ch == "p" or code == 25 then
          state = "paused"
        end
      elseif state == "paused" then
        if ch == "q" or code == 16 then
          break
        elseif ch == "p" or code == 25 then
          state = "playing"
          lastStep = now()
          lastScore = now()
        end
      elseif state == "gameover" then
        if ch == "q" or code == 16 then
          break
        elseif ch == "m" or code == 50 then
          state = "menu"
        elseif ch == "\r" or ch == "\n" or ch == "r" or code == 28 or code == 19 then
          reset()
          state = "playing"
        end
      end
    elseif ev == "touch" then
      local tx, ty = tonumber(chr), tonumber(code)
      if state == "menu" then
        local bw, bh = math.min(w - 6, 40), 10
        local bx, by = math.floor((w - bw) / 2), math.floor(h / 2) - 5
        if tx and ty and tx >= bx and tx <= bx + bw and ty >= by and ty <= by + bh then
          if ty == by + 4 then
            menuIdx = 1
            reset()
            state = "playing"
          elseif ty == by + 5 then
            menuIdx = 2
            toggleSpeed()
          elseif ty == by + 6 then
            break
          end
        end
      elseif state == "gameover" then
        reset()
        state = "playing"
      elseif state == "playing" and tx then
        if tx < laneX(lane) then moveLeft()
        elseif tx > laneX(lane) then moveRight()
        end
      end
    end

    if state == "playing" then
      step()
    end

    render()
  end
end

local ok, err = pcall(run)
if not ok then
  local p = getPalette()
  local w, h = getSize()
  rectBg(1, 1, w, h, p.danger)
  put(2, 2, "Erro no Desvio no Reator:", p.text, p.danger)
  put(2, 3, tostring(err), p.player, p.danger)
  pull(2.0)
end
