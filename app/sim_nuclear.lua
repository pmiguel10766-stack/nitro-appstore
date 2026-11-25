-- Simulacao Nuclear 2D - Nitro OS App
local CFG_NAME = "sim_nuclear_cfg"

local function now()
  if type(nitro) == "table" and type(nitro.uptime) == "function" then
    local ok, t = pcall(nitro.uptime)
    if ok and type(t) == "number" then return t end
  end
  return 0
end

local function getSize()
  local w = (type(nitro) == "table" and tonumber(nitro.width)) or 60
  local h = (type(nitro) == "table" and tonumber(nitro.height)) or 22
  if type(nitro) == "table" and type(nitro.gpu) == "table" and type(nitro.gpu.getResolution) == "function" then
    local ok, gw, gh = pcall(nitro.gpu.getResolution)
    if ok and type(gw) == "number" and type(gh) == "number" then
      w, h = gw, gh
    end
  end
  return math.max(44, math.floor(w)), math.max(16, math.floor(h))
end

local function getPalette()
  local c = (type(nitro) == "table" and type(nitro.colors)) or {}
  return {
    bg     = c.black  or c.bg     or 0x090A0F,
    panel  = c.gray   or c.panel  or 0x111827,
    wall   = c.blue   or c.accent or 0x2563EB,
    accent = c.cyan   or c.blue   or 0x38BDF8,
    danger = c.red    or 0xEF4444,
    warn   = c.yellow or 0xFACC15,
    ok     = c.green  or 0x22C55E,
    text   = c.white  or 0xF8FAFC,
    muted  = c.silver or c.gray   or 0x94A3B8
  }
end

local function rect(x, y, w, h, bg, fg, ch)
  if w <= 0 or h <= 0 then return end
  if type(nitro) == "table" and type(nitro.rect) == "function" then
    pcall(nitro.rect, x, y, w, h, bg, fg, ch or " ")
  elseif type(nitro) == "table" and type(nitro.gpu) == "table" and type(nitro.gpu.fill) == "function" then
    if bg and type(nitro.gpu.setBackground) == "function" then pcall(nitro.gpu.setBackground, bg) end
    if fg and type(nitro.gpu.setForeground) == "function" then pcall(nitro.gpu.setForeground, fg) end
    pcall(nitro.gpu.fill, x, y, w, h, ch or " ")
  end
end

local function box(x, y, w, h, bg, fg)
  if type(nitro) == "table" and type(nitro.box) == "function" then
    pcall(nitro.box, x, y, w, h, bg, fg)
  else
    rect(x, y, w, h, bg, fg, " ")
    if type(nitro) == "table" and type(nitro.put) == "function" then
      pcall(nitro.put, x, y, string.rep("▀", math.max(1, w)), fg, bg)
      pcall(nitro.put, x, y + h - 1, string.rep("▄", math.max(1, w)), fg, bg)
    end
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

local function pull(dt)
  if type(nitro) == "table" and type(nitro.pull) == "function" then
    local ok, ev, a, b, c = pcall(nitro.pull, dt or 0.05)
    if ok then return ev, a, b, c end
  end
  return nil
end

local function loadRecord()
  if type(nitro) == "table" and type(nitro.cfg) == "table" and type(nitro.cfg.load) == "function" then
    local ok, data = pcall(nitro.cfg.load, CFG_NAME)
    if ok and type(data) == "table" then
      return math.max(0, math.floor(tonumber(data.recorde) or 0))
    end
  end
  return 0
end

local function saveRecord(rec)
  if type(nitro) == "table" and type(nitro.cfg) == "table" and type(nitro.cfg.save) == "function" then
    pcall(nitro.cfg.save, CFG_NAME, { recorde = math.max(0, math.floor(tonumber(rec) or 0)) })
  end
end

local function run()
  local w, h = getSize()
  local pal = getPalette()
  local best = loadRecord()

  -- Mapa 2D da sala de controle/reator
  local mapX1, mapY1 = 2, 4
  local mapW = math.max(24, math.floor(w * 0.56))
  local mapH = math.max(10, h - 6)
  local mapX2 = mapX1 + mapW - 1
  local mapY2 = mapY1 + mapH - 1

  -- Painel lateral de telemetria
  local hudX = mapX2 + 2
  local hudW = math.max(16, w - hudX)

  -- Estacoes no mapa 2D
  local stations = {
    { id = "core",  tag = "[N] NUCLEO", x = mapX1 + 4,              y = mapY1 + 2, w = 8, h = 3 },
    { id = "pump",  tag = "[P] PUMP",   x = mapX2 - 11,             y = mapY1 + 2, w = 8, h = 3 },
    { id = "turb",  tag = "[T] TURB",   x = mapX2 - 11,             y = mapY2 - 4, w = 8, h = 3 },
    { id = "panel", tag = "[C] PAINEL", x = mapX1 + 4,              y = mapY2 - 4, w = 9, h = 3 }
  }

  local state = "playing" -- "playing", "paused", "gameover"
  local px = math.floor((mapX1 + mapX2) / 2)
  local py = math.floor((mapY1 + mapY2) / 2)

  local temp = 310        -- C
  local water = 75        -- %
  local pumpOn = true
  local controlRod = 45   -- % (0 = barras inseridas/AZ-5, 100 = potencia alta)
  local rpm = 1200
  local mw = 180
  local score = 0
  local msg = "Ande com WASD e use [E] nas estacoes."
  local lastTick = now()

  local function reset()
    px = math.floor((mapX1 + mapX2) / 2)
    py = math.floor((mapY1 + mapY2) / 2)
    temp = 310
    water = 75
    pumpOn = true
    controlRod = 45
    rpm = 1200
    mw = 180
    score = 0
    msg = "Turno reiniciado. Monitore calor e agua!"
    state = "playing"
    lastTick = now()
  end

  local function nearStation(st)
    local cx = st.x + math.floor(st.w / 2)
    local cy = st.y + math.floor(st.h / 2)
    return math.abs(px - cx) <= math.floor(st.w / 2) + 2 and math.abs(py - cy) <= math.floor(st.h / 2) + 2
  end

  local function interact()
    if nearStation(stations[1]) then -- NUCLEO: ajusta potencia/barras
      controlRod = (controlRod >= 80) and 25 or (controlRod + 25)
      msg = string.format("Nucleo: potencia/barras em %d%%", controlRod)
    elseif nearStation(stations[2]) then -- PUMP: alterna bomba de agua
      pumpOn = not pumpOn
      msg = pumpOn and "Pump LIGADA: bombeando refrigerante" or "Pump DESLIGADA: agua caindo!"
    elseif nearStation(stations[3]) then -- TURBINA: valvula de vapor / alivio RPM
      if rpm > 2600 then
        rpm = math.max(900, rpm - 900)
        score = score + 10
        msg = "Turbina: alivio de pressao/RPM aplicado!"
      else
        msg = string.format("Turbina estavel em %d RPM (%d MW)", math.floor(rpm), math.floor(mw))
      end
    elseif nearStation(stations[4]) then -- PAINEL NUCLEAR: aciona resfriamento AZ-5
      controlRod = 10
      pumpOn = true
      water = math.min(100, water + 15)
      msg = "Painel: AZ-5 / resfriamento reforçado!"
    else
      msg = "Aproxime-se de [N] Nucleo, [P] Pump, [T] Turb ou [C] Painel."
    end
  end

  local function move(dx, dy)
    local nx = math.max(mapX1 + 1, math.min(mapX2 - 1, px + dx))
    local ny = math.max(mapY1 + 1, math.min(mapY2 - 1, py + dy))
    px, py = nx, ny
  end

  local function step()
    local t = now()
    if t - lastTick < 0.25 then return end
    local dt = math.min(1.0, t - lastTick)
    lastTick = t

    -- Agua e bomba
    if pumpOn then
      water = math.min(100, water + 4.5 * dt * 4)
    else
      water = math.max(0, water - 5.0 * dt * 4)
    end

    -- Calor do nucleo vs resfriamento
    local heatGen = (controlRod / 100) * 14.0
    local cooling = (water / 100) * (pumpOn and 11.5 or 4.0)
    temp = math.max(25, temp + (heatGen - cooling) * dt * 4)

    -- Turbina e geracao
    local steam = math.max(0, (temp - 140) / 10)
    local targetRpm = steam * 420
    rpm = math.max(0, rpm + (targetRpm - rpm) * 0.35)
    mw = math.max(0, (rpm / 3000) * 600)

    if temp < 850 and rpm < 3400 then
      score = score + math.max(1, math.floor(mw / 120))
    end

    -- Condicoes criticas
    if temp >= 1000 then
      msg = "DERRETIMENTO CRITICO! Temperatura acima de 1000C!"
      state = "gameover"
    elseif rpm >= 3600 then
      msg = "SOBREVELOCIDADE NA TURBINA! Falha mecanica!"
      state = "gameover"
    end

    if state == "gameover" then
      local pts = math.floor(score)
      if pts > best then
        best = pts
        saveRecord(best)
      end
    end
  end

  local function render()
    rect(1, 1, w, h, pal.bg, pal.text, " ")

    -- Barra superior
    rect(1, 1, w, 1, pal.panel, pal.text, " ")
    put(2, 1, "SIMULACAO NUCLEAR 2D // USINA NITRO", pal.accent, pal.panel)
    put(math.max(2, w - 22), 1, string.format("Pts: %-5d Rec: %-5d", math.floor(score), best), pal.warn, pal.panel)

    -- Mapa 2D da usina
    box(mapX1, mapY1, mapW, mapH, pal.bg, pal.wall)
    put(mapX1 + 2, mapY1, " SALA DE CONTROLE & REATOR ", pal.accent, pal.bg)

    -- Estacoes
    for _, st in ipairs(stations) do
      local active = nearStation(st)
      local bcol = active and pal.warn or pal.accent
      if st.id == "core" and temp >= 750 then bcol = pal.danger end
      if st.id == "pump" and not pumpOn then bcol = pal.danger end
      box(st.x, st.y, st.w, st.h, pal.panel, bcol)
      put(st.x + 1, st.y + 1, st.tag, active and pal.warn or pal.text, pal.panel)
    end

    -- Operador 2D
    put(px, py, "@", pal.ok, pal.bg)

    -- Painel lateral de telemetria
    box(hudX, mapY1, hudW, mapH, pal.panel, pal.wall)
    put(hudX + 2, mapY1 + 1, "PAINEL NUCLEAR", pal.warn, pal.panel)

    local tempCol = (temp >= 800) and pal.danger or ((temp >= 550) and pal.warn or pal.ok)
    put(hudX + 2, mapY1 + 3, string.format("Nucleo : %d C", math.floor(temp)), tempCol, pal.panel)
    put(hudX + 2, mapY1 + 4, string.format("Barras : %d%%", controlRod), pal.text, pal.panel)
    put(hudX + 2, mapY1 + 5, string.format("Agua   : %d%%", math.floor(water)), pal.accent, pal.panel)
    put(hudX + 2, mapY1 + 6, string.format("Pump   : %s", pumpOn and "ON" or "OFF"), pumpOn and pal.ok or pal.danger, pal.panel)
    put(hudX + 2, mapY1 + 7, string.format("Turbina: %d RPM", math.floor(rpm)), (rpm > 2800) and pal.danger or pal.text, pal.panel)
    put(hudX + 2, mapY1 + 8, string.format("Potencia: %d MW", math.floor(mw)), pal.ok, pal.panel)

    -- Mensagem de status
    put(2, h - 2, string.sub(msg, 1, w - 4), pal.text, pal.bg)
    put(2, h - 1, "[WASD/Setas] Andar  [E/Espaco] Interagir  [P] Pausa  [Q] Sair", pal.muted, pal.bg)

    if state == "paused" then
      local bw, bh = 30, 3
      local bx, by = math.floor((w - bw) / 2), math.floor(h / 2) - 1
      box(bx, by, bw, bh, pal.panel, pal.warn)
      put(bx + 3, by + 1, "PAUSADO - [P] continuar", pal.warn, pal.panel)
    elseif state == "gameover" then
      local bw, bh = math.min(w - 6, 42), 7
      local bx, by = math.floor((w - bw) / 2), math.floor(h / 2) - 3
      box(bx, by, bw, bh, pal.danger, pal.text)
      put(bx + 2, by + 1, "EMERGENCIA NA USINA!", pal.text, pal.danger)
      put(bx + 2, by + 2, string.format("Pts: %d  Rec: %d", math.floor(score), best), pal.warn, pal.danger)
      put(bx + 2, by + 4, "[R/Enter] Reiniciar  [Q] Sair", pal.text, pal.danger)
    end
  end

  while true do
    local ev, a, b = pull(0.05)

    if ev == "key_down" or ev == "key" then
      local code = tonumber(b)
      local ch = type(a) == "number" and string.char(a):lower() or tostring(a or ""):lower()

      if ch == "q" or code == 16 then
        break
      elseif ch == "p" or code == 25 then
        if state == "playing" then
          state = "paused"
        elseif state == "paused" then
          state = "playing"
          lastTick = now()
        end
      elseif state == "gameover" then
        if ch == "r" or ch == "\r" or ch == "\n" or code == 19 or code == 28 then
          reset()
        end
      elseif state == "playing" then
        if code == 200 or ch == "w" then move(0, -1)
        elseif code == 208 or ch == "s" then move(0, 1)
        elseif code == 203 or ch == "a" then move(-1, 0)
        elseif code == 205 or ch == "d" then move(1, 0)
        elseif ch == "e" or ch == " " or code == 18 or code == 57 then interact()
        end
      end
    elseif ev == "touch" or ev == "click" then
      local tx, ty = tonumber(a), tonumber(b)
      if state == "gameover" then
        reset()
      elseif state == "playing" and tx and ty then
        -- Se tocar perto de uma estacao, anda e interage; senao move em direcao ao toque
        for _, st in ipairs(stations) do
          if tx >= st.x and tx <= st.x + st.w and ty >= st.y and ty <= st.y + st.h then
            px = math.max(mapX1 + 1, math.min(mapX2 - 1, st.x + math.floor(st.w / 2)))
            py = math.max(mapY1 + 1, math.min(mapY2 - 1, st.y + st.h))
            interact()
            break
          end
        end
        if math.abs(tx - px) >= math.abs(ty - py) then
          move((tx < px) and -1 or 1, 0)
        else
          move(0, (ty < py) and -1 or 1)
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
  rect(1, 1, w, h, p.danger, p.text, " ")
  put(2, 2, "Erro na Simulacao Nuclear 2D:", p.text, p.danger)
  put(2, 3, tostring(err), p.warn, p.danger)
  pull(2.0)
end
