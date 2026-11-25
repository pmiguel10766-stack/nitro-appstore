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
    bg     = c.bg     or 0x090A0F,
    panel  = c.panel  or c.barbg or 0x111827,
    wall   = c.accent or 0x2563EB,
    accent = c.accent or 0x38BDF8,
    danger = c.err    or 0xEF4444,
    warn   = c.warn   or 0xFACC15,
    ok     = c.ok     or 0x22C55E,
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

  local mapX1, mapY1 = 2, 4
  local mapW = math.max(24, math.floor(w * 0.56))
  local mapH = math.max(10, h - 6)
  local mapX2 = mapX1 + mapW - 1
  local mapY2 = mapY1 + mapH - 1

  local hudX = mapX2 + 2
  local hudW = math.max(16, w - hudX)

  local stations = {
    { id = "core",  tag = "[N] NUCLEO", x = mapX1 + 4,  y = mapY1 + 2,     w = 8, h = 3 },
    { id = "pump",  tag = "[P] PUMP",   x = mapX2 - 11, y = mapY1 + 2,     w = 8, h = 3 },
    { id = "turb",  tag = "[T] TURB",   x = mapX2 - 11, y = mapY2 - 4,     w = 8, h = 3 },
    { id = "panel", tag = "[C] PAINEL", x = mapX1 + 4,  y = mapY2 - 4,     w = 9, h = 3 }
  }

  local state = "playing" -- "playing", "paused", "gameover"
  local px = math.floor((mapX1 + mapX2) / 2)
  local py = math.floor((mapY1 + mapY2) / 2)

  local temp = 310
  local water = 75
  local pumpOn = true
  local controlRod = 45
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
    if nearStation(stations[1]) then
      controlRod = (controlRod >= 80) and 25 or (controlRod + 25)
      msg = string.format("Nucleo: potencia/barras em %d%%", controlRod)
    elseif nearStation(stations[2]) then
      pumpOn = not pumpOn
      msg = pumpOn and "Pump LIGADA: bombeando refrigerante" or "Pump DESLIGADA: agua caindo!"
    elseif nearStation(stations[3]) then
      if rpm > 2600 then
        rpm = math.max(900, rpm - 900)
        score = score + 10
        msg = "Turbina: alivio de pressao/RPM aplicado!"
      else
        msg = string.format("Turbina estavel em %d RPM (%d MW)", math.floor(rpm), math.floor(mw))
      end
    elseif nearStation(stations[4]) then
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

    if pumpOn then
      water = math.min(100, water + 4.5 * dt * 4)
    else
      water = math.max(0, water - 5.0 * dt * 4)
    end

    local heatGen = (controlRod / 100) * 14.0
    local cooling = (water / 100) * (pumpOn and 11.5 or 4.0)
    temp = math.max(25, temp + (heatGen - cooling) * dt * 4)

    local steam = math.max(0, (temp - 140) / 10)
    local targetRpm = steam * 420
    rpm = math.max(0, rpm + (targetRpm - rpm) * 0.35)
    mw = math.max(0, (rpm / 3000) * 600)

    if temp < 850 and rpm < 3400 then
      score = score + math.max(1, math.floor(mw / 120))
    end

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
    rectBg(1, 1, w, h, pal.bg)

    rectBg(1, 1, w, 1, pal.panel)
    put(2, 1, "SIMULACAO NUCLEAR 2D // USINA NITRO", pal.accent, pal.panel)
    put(math.max(2, w - 22), 1, string.format("Pts: %-5d Rec: %-5d", math.floor(score), best), pal.warn, pal.panel)

    box(mapX1, mapY1, mapW, mapH, pal.bg, pal.wall)
    put(mapX1 + 2, mapY1, " SALA DE CONTROLE & REATOR ", pal.accent, pal.bg)

    for _, st in ipairs(stations) do
      local active = nearStation(st)
      local bcol = active and pal.warn or pal.accent
      if st.id == "core" and temp >= 750 then bcol = pal.danger end
      if st.id == "pump" and not pumpOn then bcol = pal.danger end
      box(st.x, st.y, st.w, st.h, pal.panel, bcol)
      put(st.x + 1, st.y + 1, st.tag, active and pal.warn or pal.text, pal.panel)
    end

    put(px, py, "@", pal.ok, pal.bg)

    box(hudX, mapY1, hudW, mapH, pal.panel, pal.wall)
    put(hudX + 2, mapY1 + 1, "PAINEL NUCLEAR", pal.warn, pal.panel)

    local tempCol = (temp >= 800) and pal.danger or ((temp >= 550) and pal.warn or pal.ok)
    put(hudX + 2, mapY1 + 3, string.format("Nucleo : %d C", math.floor(temp)), tempCol, pal.panel)
    put(hudX + 2, mapY1 + 4, string.format("Barras : %d%%", controlRod), pal.text, pal.panel)
    put(hudX + 2, mapY1 + 5, string.format("Agua   : %d%%", math.floor(water)), pal.accent, pal.panel)
    put(hudX + 2, mapY1 + 6, string.format("Pump   : %s", pumpOn and "ON" or "OFF"), pumpOn and pal.ok or pal.danger, pal.panel)
    put(hudX + 2, mapY1 + 7, string.format("Turbina: %d RPM", math.floor(rpm)), (rpm > 2800) and pal.danger or pal.text, pal.panel)
    put(hudX + 2, mapY1 + 8, string.format("Potencia: %d MW", math.floor(mw)), pal.ok, pal.panel)

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
    local ev, _, chr, code = pull(0.05)

    if ev == "key_down" then
      local ch = (type(chr) == "number" and chr > 0 and chr < 256) and string.char(chr):lower() or ""
      code = tonumber(code)

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
    elseif ev == "touch" then
      local tx, ty = tonumber(chr), tonumber(code)
      if state == "gameover" then
        reset()
      elseif state == "playing" and tx and ty then
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
  rectBg(1, 1, w, h, p.danger)
  put(2, 2, "Erro na Simulacao Nuclear 2D:", p.text, p.danger)
  put(2, 3, tostring(err), p.warn, p.danger)
  pull(2.0)
end
