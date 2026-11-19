-- name: NAS Pessoal
-- desc: Servidor de arquivos pela Rede Local
-- ver: 1.0
-- LIMITES:
-- - A conexao e so pela Rede Local (alcance do sinal). Nao ha acesso pela internet.
-- - O servidor so responde com o app aberto.
-- - A senha trafega em texto puro; e protecao leve, nao criptografia.
-- - nitro.pull(0.05) e usado durante envio de arquivos para ceder tempo;
--   eventos (rede/teclado) podem ser consumidos nesse intervalo.

local SHARE_DIR = "/Download/nuvem/"
local PORT = 4343
local MAX_FILE_SIZE = 65536
local MAX_CHUNK_SIZE = 1700

local state = {
  initialized = false,
  hasCard = false,
  portOpen = false,
  serverId = "desconhecido",
  files = {},
  totalBytes = 0,
  scroll = 0,
  logs = {},
  password = "",
  editingPass = false,
  passInput = "",
  authedClients = {},
  uploads = {},
  lastBox = nil
}

local function addLog(msg)
  local clean = tostring(msg or ""):gsub("[^\32-\126]", "?")
  if #clean > 52 then
    clean = clean:sub(1, 49) .. "..."
  end
  table.insert(state.logs, 1, clean)
  if #state.logs > 30 then
    table.remove(state.logs)
  end
end

local function isValidName(name)
  if type(name) ~= "string" or #name == 0 or #name > 64 then
    return false
  end
  if name:sub(1, 1) == "." then
    return false
  end
  if name:find("%.%.", 1, true) or name:find("/", 1, true) or name:find("\\", 1, true) then
    return false
  end
  if not name:match("^[A-Za-z0-9_%-%. ]+$") then
    return false
  end
  return true
end

local function ensureShareDir(nitro)
  local list = nitro.listDir(SHARE_DIR)
  if type(list) == "table" then
    return true
  end
  local ok = nitro.writeFile(SHARE_DIR .. ".keep", "NAS Pessoal\n")
  if ok then
    addLog("Pasta " .. SHARE_DIR .. " criada")
    return true
  end
  return false
end

local function refreshFiles(nitro)
  ensureShareDir(nitro)
  local list = nitro.listDir(SHARE_DIR)
  state.files = {}
  state.totalBytes = 0
  if type(list) == "table" then
    for _, name in ipairs(list) do
      if isValidName(name) and name ~= ".keep" then
        local content = nitro.readFile(SHARE_DIR .. name)
        local sz = content and #content or 0
        state.totalBytes = state.totalBytes + sz
        table.insert(state.files, { name = name, size = sz })
      end
    end
  end
  if state.scroll > math.max(0, #state.files - 5) then
    state.scroll = math.max(0, #state.files - 5)
  end
end

local function getNet(nitro)
  if type(nitro) == "table" and type(nitro.net) == "table" then
    return nitro.net
  end
  return nil
end

local function syncNet(nitro, logChange)
  local net = getNet(nitro)
  if not net then
    state.hasCard = false
    state.portOpen = false
    state.serverId = "desconhecido"
    if logChange then
      addLog("API nitro.net indisponivel")
    end
    return
  end

  local hasCard = false
  if type(net.card) == "function" then
    hasCard = net.card() and true or false
  elseif type(net.id) == "function" then
    hasCard = net.id() ~= nil
  end
  state.hasCard = hasCard

  if state.hasCard then
    local idVal = type(net.id) == "function" and net.id() or "sem-id"
    state.serverId = tostring(idVal or "sem-id")
    if not state.portOpen and type(net.open) == "function" then
      state.portOpen = net.open(PORT) and true or false
      if state.portOpen then
        addLog("Porta " .. PORT .. " aberta. ID: " .. state.serverId:sub(1, 8))
      elseif logChange then
        addLog("Permissao negada na porta " .. PORT)
      end
    end
  else
    state.portOpen = false
    if logChange then
      addLog("Sem placa sem fio detectada")
    end
  end
end

local function init(nitro)
  if state.initialized then
    return
  end
  state.initialized = true
  syncNet(nitro, true)
  refreshFiles(nitro)
end

local function sendReply(nitro, addr, text)
  local net = getNet(nitro)
  if state.hasCard and state.portOpen and net and type(net.send) == "function" then
    if #text <= 1800 then
      net.send(addr, PORT, text)
    end
  end
end

local function splitCmd(msg)
  local p1 = msg:find("|", 1, true)
  if not p1 then
    return msg, nil
  end
  return msg:sub(1, p1 - 1), msg:sub(p1 + 1)
end

local function splitTwo(str)
  if not str then
    return nil, nil
  end
  local p1 = str:find("|", 1, true)
  if not p1 then
    return str, nil
  end
  return str:sub(1, p1 - 1), str:sub(p1 + 1)
end

local function splitThree(str)
  if not str then
    return nil, nil, nil
  end
  local p1 = str:find("|", 1, true)
  if not p1 then
    return str, nil, nil
  end
  local a = str:sub(1, p1 - 1)
  local rest = str:sub(p1 + 1)
  local p2 = rest:find("|", 1, true)
  if not p2 then
    return a, rest, nil
  end
  return a, rest:sub(1, p2 - 1), rest:sub(p2 + 1)
end

local function isAuthed(addr)
  if state.password == "" then
    return true
  end
  return state.authedClients[addr] == true
end

local function handleList(nitro, addr, rest)
  local rel = rest or ""
  if rel ~= "" and not isValidName(rel) then
    sendReply(nitro, addr, "ERR|caminho invalido")
    return
  end
  refreshFiles(nitro)
  local count = #state.files
  if count == 0 then
    sendReply(nitro, addr, "LISTR|0|")
  else
    for i, f in ipairs(state.files) do
      sendReply(nitro, addr, "LISTR|" .. i .. "|" .. f.name .. "|" .. f.size)
    end
  end
  addLog("LIST de " .. addr:sub(1, 8) .. " (" .. count .. " itens)")
end

local function handleGet(nitro, addr, rest)
  local name = rest or ""
  if not isValidName(name) then
    sendReply(nitro, addr, "ERR|nome invalido")
    return
  end
  local data = nitro.readFile(SHARE_DIR .. name)
  if not data then
    sendReply(nitro, addr, "ERR|arquivo nao encontrado")
    addLog("GET falhou: " .. name)
    return
  end
  local totalSize = #data
  if totalSize > MAX_FILE_SIZE then
    sendReply(nitro, addr, "ERR|grande demais")
    return
  end
  local totalParts = math.max(1, math.ceil(totalSize / MAX_CHUNK_SIZE))
  sendReply(nitro, addr, "FILE|" .. name .. "|" .. totalSize .. "|" .. totalParts)
  nitro.pull(0.05)
  for i = 1, totalParts do
    local sIdx = (i - 1) * MAX_CHUNK_SIZE + 1
    local eIdx = math.min(totalSize, i * MAX_CHUNK_SIZE)
    local chunk = data:sub(sIdx, eIdx)
    sendReply(nitro, addr, "CHUNK|" .. i .. "|" .. chunk)
    nitro.pull(0.05)
  end
  sendReply(nitro, addr, "END|" .. name)
  addLog("Enviado: " .. name .. " (" .. totalSize .. "B)")
end

local function handlePut(nitro, addr, rest)
  local name, sizeStr, partsStr = splitThree(rest)
  local size = tonumber(sizeStr)
  local parts = tonumber(partsStr)
  if not isValidName(name) or not size or not parts or size < 0 or parts < 1 then
    sendReply(nitro, addr, "ERR|parametros invalidos")
    return
  end
  if size > MAX_FILE_SIZE then
    sendReply(nitro, addr, "ERR|grande demais")
    addLog("PUT bloqueado (>64KB): " .. name)
    return
  end
  state.uploads[addr] = {
    name = name,
    size = math.floor(size),
    parts = math.floor(parts),
    chunks = {},
    received = 0
  }
  sendReply(nitro, addr, "OK|pronto")
  addLog("Recebendo: " .. name .. " (" .. size .. "B)")
end

local function handleChunk(nitro, addr, rest)
  local up = state.uploads[addr]
  if not up then
    sendReply(nitro, addr, "ERR|nenhum PUT ativo")
    return
  end
  local nStr, data = splitTwo(rest)
  local n = tonumber(nStr)
  if not n or n < 1 or n > up.parts or type(data) ~= "string" then
    sendReply(nitro, addr, "ERR|parte invalida")
    return
  end
  if not up.chunks[n] then
    up.received = up.received + 1
  end
  up.chunks[n] = data
end

local function handleEnd(nitro, addr, rest)
  local up = state.uploads[addr]
  local name = rest or ""
  if not up or up.name ~= name then
    sendReply(nitro, addr, "ERR|envio inconsistente")
    state.uploads[addr] = nil
    return
  end
  if up.received ~= up.parts then
    sendReply(nitro, addr, "ERR|partes incompletas")
    state.uploads[addr] = nil
    addLog("PUT falhou (partes): " .. name)
    return
  end
  local buf = {}
  for i = 1, up.parts do
    if not up.chunks[i] then
      sendReply(nitro, addr, "ERR|parte faltando")
      state.uploads[addr] = nil
      return
    end
    buf[i] = up.chunks[i]
  end
  local fullData = table.concat(buf)
  if #fullData ~= up.size or #fullData > MAX_FILE_SIZE then
    sendReply(nitro, addr, "ERR|tamanho nao confere")
    state.uploads[addr] = nil
    addLog("PUT falhou (tamanho): " .. name)
    return
  end
  ensureShareDir(nitro)
  local ok = nitro.writeFile(SHARE_DIR .. up.name, fullData)
  state.uploads[addr] = nil
  if ok then
    refreshFiles(nitro)
    sendReply(nitro, addr, "OK|salvo")
    addLog("Salvo: " .. up.name .. " (" .. #fullData .. "B)")
  else
    sendReply(nitro, addr, "ERR|falha ao gravar")
    addLog("Erro gravar: " .. up.name)
  end
end

local function getBox(self)
  local x0 = tonumber(self and self.x) or 1
  local y0 = tonumber(self and self.y) or 1
  local w = tonumber(self and self.w) or 60
  local h = tonumber(self and self.h) or 20
  return x0, y0, w, h
end

return {
  title = "NAS Pessoal",
  w = 60,
  h = 20,

  body = function(self, nitro)
    init(nitro)
    local c = nitro.colors
    local x0, y0, w, h = getBox(self)
    state.lastBox = { x0 = x0, y0 = y0, w = w, h = h }

    local innerW = math.max(20, w - 2)
    local innerH = math.max(10, h - 1)
    nitro.rect(x0 + 1, y0 + 1, innerW, innerH, c.bg)

    local hdrH = math.min(3, innerH)
    nitro.rect(x0 + 1, y0 + 1, innerW, hdrH, c.panel)

    local cardTxt = state.hasCard and (state.portOpen and "Wi-Fi: ON" or "Wi-Fi: BLOQ") or "Wi-Fi: OFF"
    local cardCol = (state.hasCard and state.portOpen) and c.ok or c.err
    nitro.put(x0 + 2, y0 + 1, "ID: " .. state.serverId:sub(1, 14), c.text, c.panel, 20)
    nitro.put(x0 + 23, y0 + 1, cardTxt, cardCol, c.panel, 13)

    local btnLabel = state.editingPass and "[Salvar]" or "[Definir senha]"
    local btnCol = state.editingPass and c.ok or c.accent
    nitro.put(x0 + 38, y0 + 1, btnLabel, c.bg, btnCol, math.min(18, innerW - 37))

    if hdrH >= 2 then
      local passStatus = (state.password == "") and "Aberta" or "Ativa"
      local passCol = (state.password == "") and c.warn or c.ok
      if state.editingPass then
        nitro.put(x0 + 2, y0 + 2, "Nova senha: " .. state.passInput .. "_", c.accent, c.panel, innerW - 2)
      else
        nitro.put(x0 + 2, y0 + 2, "Pasta: " .. SHARE_DIR, c.dim, c.panel, 24)
        nitro.put(x0 + 27, y0 + 2, "Senha: " .. passStatus, passCol, c.panel, 14)
        nitro.put(x0 + 43, y0 + 2, "[F5] Atual.", c.text, c.panel, math.min(13, innerW - 42))
      end
    end

    if hdrH >= 3 then
      local kbUsed = string.format("%.1f", state.totalBytes / 1024)
      nitro.put(x0 + 2, y0 + 3, "Arq: " .. #state.files .. " | Usado: " .. kbUsed .. " KB (max 64KB/arq)", c.text, c.panel, innerW - 2)
    end

    local filesTitleY = y0 + 5
    local filesBoxY = y0 + 6
    local filesBoxH = 5
    if filesTitleY <= y0 + innerH then
      nitro.put(x0 + 2, filesTitleY, "ARQUIVOS COMPARTILHADOS (Setas: rolar)", c.accent, c.bg, innerW - 2)
    end
    if filesBoxY <= y0 + innerH then
      local actualFilesH = math.min(filesBoxH, (y0 + innerH) - filesBoxY + 1)
      nitro.rect(x0 + 2, filesBoxY, innerW - 2, actualFilesH, c.panel)
      if #state.files == 0 then
        nitro.put(x0 + 3, filesBoxY + 1, "(Nenhum arquivo em " .. SHARE_DIR .. ")", c.dim, c.panel, innerW - 4)
      else
        for row = 0, actualFilesH - 1 do
          local idx = state.scroll + row + 1
          local f = state.files[idx]
          if f then
            local szStr = string.format("%6d B", f.size)
            nitro.put(x0 + 3, filesBoxY + row, f.name, c.text, c.panel, math.max(8, innerW - 14))
            nitro.put(x0 + innerW - 10, filesBoxY + row, szStr, c.dim, c.panel, 10)
          end
        end
      end
    end

    local logTitleY = y0 + 12
    local logBoxY = y0 + 13
    if logTitleY <= y0 + innerH then
      nitro.put(x0 + 2, logTitleY, "LOG DE EVENTOS", c.accent, c.bg, innerW - 2)
    end
    if logBoxY <= y0 + innerH then
      local actualLogH = math.min(5, (y0 + innerH) - logBoxY + 1)
      if actualLogH > 0 then
        nitro.rect(x0 + 2, logBoxY, innerW - 2, actualLogH, c.panel)
        if #state.logs == 0 then
          nitro.put(x0 + 3, logBoxY + 1, "Aguardando conexoes na porta 4343...", c.dim, c.panel, innerW - 4)
        else
          for row = 0, actualLogH - 1 do
            local entry = state.logs[row + 1]
            if entry then
              nitro.put(x0 + 3, logBoxY + row, "> " .. entry, c.text, c.panel, innerW - 4)
            end
          end
        end
      end
    end
  end,

  onKey = function(self, char, code, nitro)
    if state.editingPass then
      if char == 28 or code == 28 then
        state.password = state.passInput
        state.editingPass = false
        state.authedClients = {}
        if state.password == "" then
          addLog("Senha removida (acesso livre)")
        else
          addLog("Senha definida (" .. #state.password .. " chars)")
        end
        return true
      elseif char == 1 or code == 1 then
        state.editingPass = false
        state.passInput = state.password
        return true
      elseif char == 14 or code == 14 then
        if #state.passInput > 0 then
          state.passInput = state.passInput:sub(1, -2)
        end
        return true
      elseif type(char) == "number" and char >= 32 and char <= 126 then
        local ch = string.char(char)
        if ch ~= "|" and #state.passInput < 24 then
          state.passInput = state.passInput .. ch
          return true
        end
      end
      return true
    end

    if code == 1 then
      return false
    elseif code == 63 then
      syncNet(nitro, true)
      refreshFiles(nitro)
      addLog("Atualizado (" .. #state.files .. " arq)")
      return true
    elseif code == 200 then
      if state.scroll > 0 then
        state.scroll = state.scroll - 1
      end
      return true
    elseif code == 208 then
      if state.scroll < math.max(0, #state.files - 5) then
        state.scroll = state.scroll + 1
      end
      return true
    end
    return false
  end,

  onTouch = function(self, x, y, nitro)
    local box = state.lastBox or {}
    local x0 = box.x0 or tonumber(self and self.x) or 1
    local y0 = box.y0 or tonumber(self and self.y) or 1
    local w = box.w or tonumber(self and self.w) or 60
    local innerW = math.max(20, w - 2)

    if y == y0 + 1 and x >= x0 + 38 and x <= x0 + innerW then
      if state.editingPass then
        state.password = state.passInput
        state.editingPass = false
        state.authedClients = {}
        addLog(state.password == "" and "Senha removida" or "Senha atualizada")
      else
        state.editingPass = true
        state.passInput = state.password
      end
      return true
    elseif y == y0 + 2 and x >= x0 + 43 and x <= x0 + innerW and not state.editingPass then
      syncNet(nitro, true)
      refreshFiles(nitro)
      addLog("Lista atualizada")
      return true
    end
    return false
  end,

  onModem = function(self, addr, port, dist, msg, nitro)
    if port ~= PORT or type(msg) ~= "string" or type(addr) ~= "string" then
      return
    end
    local cmd, rest = splitCmd(msg)

    if cmd == "AUTH" then
      local pass = rest or ""
      if state.password == "" or pass == state.password then
        state.authedClients[addr] = true
        sendReply(nitro, addr, "OK|autenticado")
        addLog("AUTH ok: " .. addr:sub(1, 8))
      else
        sendReply(nitro, addr, "ERR|senha incorreta")
        addLog("AUTH falhou: " .. addr:sub(1, 8))
      end
      return
    end

    if not isAuthed(addr) then
      sendReply(nitro, addr, "ERR|autenticacao necessaria")
      return
    end

    if cmd == "LIST" then
      handleList(nitro, addr, rest)
    elseif cmd == "GET" then
      handleGet(nitro, addr, rest)
    elseif cmd == "PUT" then
      handlePut(nitro, addr, rest)
    elseif cmd == "CHUNK" then
      handleChunk(nitro, addr, rest)
    elseif cmd == "END" then
      handleEnd(nitro, addr, rest)
    else
      sendReply(nitro, addr, "ERR|comando desconhecido")
      addLog("Cmd invalido de " .. addr:sub(1, 8))
    end
  end
}
