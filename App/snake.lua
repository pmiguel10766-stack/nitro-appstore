
Repos-- App: Jogo da Cobrinha (Snake) para Nitro OS
local cl, cp = component, computer
local gpu = cl.proxy(cl.list("gpu")())
local w, h = gpu.getResolution()

-- Janela centralizada
local ww, wh = 36, 16
local wx = math.floor((w - ww) / 2) + 1
local wy = math.max(2, math.floor((h - wh) / 2) + 1)

local C = {
  bg = 0x050505, panel = 0x1A1A1A, accent = 0xFF2D2D, text = 0xFFFFFF,
  dim = 0xA0A0A0, ok = 0x3DDC84, snake = 0x3DDC84, food = 0xFF2D2D,
}

local function rect(x, y, rw, rh, bg)
  gpu.setBackground(bg)
  gpu.fill(x, y, rw, rh, " ")
end

local function put(x, y, s, fg, bg)
  gpu.setBackground(bg)
  gpu.setForeground(fg)
  gpu.set(x, y, tostring(s))
end

local function drawBox(x, y, bw, bh, title)
  rect(x, y, bw, bh, C.panel)
  local line = string.rep("─", bw - 2)
  put(x, y, "╭" .. line .. "╮", C.accent, C.panel)
  for r = 1, bh - 2 do
    put(x, y + r, "│", C.accent, C.panel)
    put(x + bw - 1, y + r, "│", C.accent, C.panel)
  end
  put(x, y + bh - 1, "╰" .. line .. "╯", C.accent, C.panel)
  if title then put(x + 2, y, " " .. title .. " ", C.text, C.panel, bw - 8) end
end

local function snakeApp()
  local gameW, gameH = ww - 4, wh - 6
  local gameX, gameY = wx + 2, wy + 3

  local snake = { { x = math.floor(gameW / 2), y = math.floor(gameH / 2) } }
  local dx, dy = 1, 0
  local food = { x = 3, y = 3 }
  local score = 0
  local gameOver = false

  local function spawnFood()
    food.x = math.random(1, gameW)
    food.y = math.random(1, gameH)
  end

  spawnFood()

  local function draw()
    drawBox(wx, wy, ww, wh, "Snake")
    put(wx + 2, wy + 1, "Pontos: " .. score, C.text, C.panel)
    put(wx + ww - 6, wy + 1, "[X]", C.bg, C.accent)

    -- Campo de jogo
    rect(gameX, gameY, gameW, gameH, 0x111111)

    -- Desenhar comida
    put(gameX + food.x - 1, gameY + food.y - 1, "●", C.food, 0x111111)

    -- Desenhar cobrinha
    for _, seg in ipairs(snake) do
      put(gameX + seg.x - 1, gameY + seg.y - 1, "■", C.snake, 0x111111)
    end

    if gameOver then
      local msg = " GAME OVER "
      rect(gameX + math.floor(gameW/2) - 6, gameY + math.floor(gameH/2), 12, 1, C.accent)
      put(gameX + math.floor(gameW/2) - 5, gameY + math.floor(gameH/2), msg, C.bg, C.accent)
    end
  end

  local function update()
    if gameOver then return end

    local head = { x = snake[1].x + dx, y = snake[1].y + dy }

    -- Colisão com paredes
    if head.x < 1 or head.x > gameW or head.y < 1 or head.y > gameH then
      gameOver = true
      return
    end

    -- Colisão com o próprio corpo
    for _, seg in ipairs(snake) do
      if head.x == seg.x and head.y == seg.y then
        gameOver = true
        return
      end
    end

    table.insert(snake, 1, head)

    -- Comer comida
    if head.x == food.x and head.y == food.y then
      score = score + 10
      spawnFood()
    else
      table.remove(snake)
    end
  end

  draw()

  while true do
    local ev, _, _, code = cp.pullSignal(0.15) -- Velocidade do jogo
    if ev == "key_down" then
      if code == 200 and dy == 0 then dx, dy = 0, -1 -- Cima
      elseif code == 208 and dy == 0 then dx, dy = 0, 1  -- Baixo
      elseif code == 203 and dx == 0 then dx, dy = -1, 0 -- Esquerda
      elseif code == 205 and dx == 0 then dx, dy = 1, 0  -- Direita
      elseif code == 1 or code == 28 then break end      -- Esc ou Enter para sair
    elseif ev == "touch" then
      -- Clicar no [X] para fechar
      local _, _, tx, ty = cp.pullSignal() -- simplificado
      break
    end

    update()
    draw()
  end
end

snakeApp()
