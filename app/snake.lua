-- App: snake.lua
-- Jogo da Cobrinha para Nitro OS (PT / EN)

local function snakeApp(env)
  local cl, cp = component, computer
  local gpu = env and env.gpu or cl.proxy(cl.list("gpu")())
  local w, h = gpu.getResolution()

  -- Idioma simples (Português por padrão)
  local T = {
    title = "Snake",
    score = "Pontos: ",
    over = " FIM DE JOGO ",
    hint = "Esc Sair"
  }

  local ww, wh = 38, 16
  local wx = math.floor((w - ww) / 2) + 1
  local wy = math.max(2, math.floor((h - wh) / 2) + 1)
  local gameW, gameH = ww - 4, wh - 6
  local gameX, gameY = wx + 2, wy + 3

  local snake = { { x = math.floor(gameW / 2), y = math.floor(gameH / 2) } }
  local dx, dy = 1, 0
  local food = { x = 4, y = 4 }
  local score = 0
  local gameOver = false

  local function rect(x, y, rw, rh, bg)
    gpu.setBackground(bg)
    gpu.fill(x, y, rw, rh, " ")
  end

  local function put(x, y, s, fg, bg)
    gpu.setBackground(bg)
    gpu.setForeground(fg)
    gpu.set(x, y, tostring(s))
  end

  local function spawnFood()
    food.x = math.random(1, gameW)
    food.y = math.random(1, gameH)
  end

  spawnFood()

  local function drawBox()
    rect(wx, wy, ww, wh, 0x1A1A1A)
    local line = string.rep("-", ww - 2)
    put(wx, wy, "+" .. line .. "+", 0xFF2D2D, 0x1A1A1A)
    for r = 1, wh - 2 do
      put(wx, wy + r, "|", 0xFF2D2D, 0x1A1A1A)
      put(wx + ww - 1, wy + r, "|", 0xFF2D2D, 0x1A1A1A)
    end
    put(wx, wy + wh - 1, "+" .. line .. "+", 0xFF2D2D, 0x1A1A1A)
    put(wx + 2, wy, " " .. T.title .. " ", 0xFFFFFF, 0x1A1A1A)
    put(wx + ww - 6, wy, "[X]", 0x050505, 0xFF2D2D)
  end

  local function draw()
    drawBox()
    put(wx + 2, wy + 1, T.score .. score, 0xFFFFFF, 0x1A1A1A)
    put(wx + 2, wy + wh - 2, T.hint, 0xA0A0A0, 0x1A1A1A)

    -- Área do jogo
    rect(gameX, gameY, gameW, gameH, 0x111111)

    -- Comida
    put(gameX + food.x - 1, gameY + food.y - 1, "O", 0xFF2D2D, 0x111111)

    -- Cobrinha
    for _, seg in ipairs(snake) do
      put(gameX + seg.x - 1, gameY + seg.y - 1, "#", 0x3DDC84, 0x111111)
    end

    if gameOver then
      local gx = gameX + math.floor((gameW - #T.over) / 2)
      local gy = gameY + math.floor(gameH / 2)
      rect(gx - 1, gy, #T.over + 2, 1, 0xFF2D2D)
      put(gx, gy, T.over, 0x050505, 0xFF2D2D)
    end
  end

  local function update()
    if gameOver then return end
    local head = { x = snake[1].x + dx, y = snake[1].y + dy }

    if head.x < 1 or head.x > gameW or head.y < 1 or head.y > gameH then
      gameOver = true
      return
    end

    for _, seg in ipairs(snake) do
      if head.x == seg.x and head.y == seg.y then
        gameOver = true
        return
      end
    end

    table.insert(snake, 1, head)

    if head.x == food.x and head.y == food.y then
      score = score + 10
      spawnFood()
    else
      table.remove(snake)
    end
  end

  draw()

  while true do
    -- Pausa obrigatória para não travar o hardware
    local ev, _, a, b = cp.pullSignal(0.12)

    if ev == "key_down" then
      if b == 200 and dy == 0 then dx, dy = 0, -1
      elseif b == 208 and dy == 0 then dx, dy = 0, 1
      elseif b == 203 and dx == 0 then dx, dy = -1, 0
      elseif b == 205 and dx == 0 then dx, dy = 1, 0
      elseif b == 1 or b == 28 then break end
    elseif ev == "touch" then
      if b == wy and a >= wx + ww - 6 and a <= wx + ww - 4 then
        break
      end
    end

    update()
    draw()
  end
end

return snakeApp
