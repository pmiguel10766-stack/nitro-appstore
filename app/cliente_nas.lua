-- name: Cliente NAS
-- desc: Cliente de arquivos pela Rede Local (porta 4343)
-- ver: 1.0
-- LIMITES:
-- - A conexao e so pela Rede Local (alcance do sinal). Nao ha acesso pela internet.
-- - O servidor NAS precisa estar com o app aberto para responder.
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
  clientId = "desconhecido",
  serverAddr = "",
  password = "",
  inputMode = nil,
  inputBuf = "",
  remoteFiles = {},
  localFiles = {},
  selectedIdx = 1,
  scroll = 0,
  logs = {},
  lastBox = nil,
  pendingAction = nil,
  transfer = nil
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
  local ok = nitro.writeFile(SHARE_DIR .. ".keep", "Cliente NAS\n")
  if ok then
    addLog("Pasta " .. SHARE_DIR .. " criada")
    return true
  end
  return false
end

local function refreshLocalFiles(nitro)
  ensureShareDir(nitro)
  local list = nitro.listDir(SHARE_DIR)
  state.localFiles = {}
  if type(list) == "table" then
    for _, name in ipairs(list) do
      if isValidName(name) and name ~= ".keep" then
        local content = nitro.readFile(SHARE_DIR .. name)
        local sz = content and #content or 0
        table.insert(state.localFiles, { name = name, size = sz })
      end
    end
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
    state.clientId = "desconhecido"
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
    state.clientId = tostring(idVal or "sem-id")
    if not state.portOpen and type(net.open) == "function" then
      state.portOpen = net.open(PORT) and true or false
      if state.portOpen then
        addLog("Porta " .. PORT .. " aberta. ID: " .. state.clientId:sub(1, 8))
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
  refreshLocalFiles(nitro)
end

local function sendToServer(nitro, text)
  if state.serverAddr == "" then
    addLog("Defina o ID/endereco do servidor")
    return false
  end
  if #text > 1800 then
    addLog("Mensagem excede 1800 bytes")
    return false
  end
  local net = getNet(nitro)
  if state.hasCard and state.portOpen and net and type(net.send) == "function" then
    local ok = net.send(state.serverAddr, PORT, text)
    if not ok then
      addLog("Falha ao enviar pacote")
    end
    return ok and true or false
  end
  addLog("Rede indisponivel para envio")
  return false
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

local function requestList(nitro)
  syncNet(nitro, false)
  if state.serverAddr == "" then
    addLog("Informe o servidor antes de listar")
    return
  end
  if state.password ~= "" then
    sendToServer(nitro, "AUTH|" .. state.password)
    state.pendingAction = "LIST"
    addLog("Autenticando e pedindo lista...")
  else
    state.remoteFiles = {}
    sendToServer(nitro, "LIST|")
    addLog("Pedindo lista ao servidor...")
  end
end

local function requestGet(nitro, name)
  if not isValidName(name) then
    addLog("Nome de arquivo invalido: " .. tostring(name))
    return
  end
  syncNet(nitro, false)
  if state.serverAddr == "" then
    addLog("Informe o servidor antes de baixar")
    return
  end
  if state.password ~= "" then
    sendToServer(nitro, "AUTH|" .. state.password)
    state.pendingAction = { type = "GET", name = name }
    addLog("Autenticando para baixar " .. name)
  else
    sendToServer(nitro, "GET|" .. name)
    addLog("Solicitando GET: " .. name)
  end
end

local function sendLocalFile(nitro, name)
  if not isValidName(name) then
    addLog("Nome invalido para envio: " .. tostring(name))
    return
  end
  syncNet(nitro, false)
  if state.serverAddr == "" then
    addLog("Informe o servidor antes de enviar")
    return
  end
  local data = nitro.readFile(SHARE_DIR .. name)
  if type(data) ~= "string" then
    addLog("Arquivo local nao encontrado: " .. name)
    return
  end
  local totalSize = #data
  if totalSize > MAX_FILE_SIZE then
    addLog("Arquivo > 64 KB bloqueado: " .. name)
    return
  end
  local totalParts = math.max(1, math.ceil(totalSize / MAX_CHUNK_SIZE))
  if not sendToServer(nitro, "PUT|" .. name .. "|" .. totalSize .. "|" .. totalParts) then
    return
  end
  nitro.pull(0.05)
  for i = 1, totalParts do
    local sIdx = (i - 1) * MAX_CHUNK_SIZE + 1
    local eIdx = math.min(totalSize, i * MAX_CHUNK_SIZE)
    local chunk = data:sub(sIdx, eIdx)
    if not sendToServer(nitro, "CHUNK|" .. i .. "|" .. chunk) then
      addLog("Envio interrompido na parte " .. i)
      return
    end
    nitro.pull(0.05)
  end
  sendToServer(nitro, "END|" .. name)
  addLog("Enviado PUT: " .. name .. " (" .. totalSize .. "B)")
end

local function requestPut(nitro, name)
  if not isValidName(name) then
    addLog("Nome invalido para PUT: " .. tostring(name))
    return
  end
  local data = nitro.readFile(SHARE_DIR .. name)
  if type(data) ~= "string" then
    addLog("Arquivo nao existe em " .. SHARE_DIR .. ": " .. name)
    return
  end
  if #data > MAX_FILE_SIZE then
    addLog("Limite de 64 KB excedido: " .. name)
    return
  end
  if state.password ~= "" then
    sendToServer(nitro, "AUTH|" .. state.password)
    state.pendingAction = { type = "PUT", name = name }
    addLog("Autenticando para enviar " .. name)
  else
    sendLocalFile(nitro, name)
  end
end

local function handleFileHeader(rest)
  local name, sizeStr, partsStr = splitThree(rest)
  local size = tonumber(sizeStr)
  local parts = tonumber(partsStr)
  if not isValidName(name) or not size or not parts or size < 0 or parts < 1 then
    addLog("Cabecalho FILE invalido")
    return
  end
  if size > MAX_FILE_SIZE then
    addLog("Arquivo remoto > 64 KB ignorado: " .. name)
    state.transfer = nil
    return
  end
  state.transfer = {
    name = name,
    size = math.floor(size),
    parts = math.floor(parts),
    chunks = {},
    received = 0
  }
  addLog("Baixando " .. name .. " (" .. size .. "B)...")
end

local function handleChunk(rest)
  local tr = state.transfer
  if not tr then
    return
  end
  local nStr, data = splitTwo(rest)
  local n = tonumber(nStr)
  if not n or n < 1 or n > tr.parts or type(data) ~= "string" then
    addLog("Parte CHUNK invalida")
    return
  end
  if not tr.chunks[n] then
    tr.received = tr.received + 1
  end
  tr.chunks[n] = data
end

local function handleEnd(nitro, rest)
  local tr = state.transfer
  local name = rest or ""
  state.transfer = nil
  if not tr or tr.name ~= name then
    addLog("END inconsistente: " .. name)
    return
  end
  if tr.received ~= tr.parts then
    addLog("Download incompleto: " .. name)
    return
  end
  local buf = {}
  for i = 1, tr.parts do
    if not tr.chunks[i] then
      addLog("Parte " .. i .. " ausente em " .. name)
      return
    end
    buf[i] = tr.chunks[i]
  end
  local fullData = table.concat(buf)
  if #fullData ~= tr.size or #fullData > MAX_FILE_SIZE then
    addLog("Tamanho divergente em " .. name)
    return
  end
  ensureShareDir(nitro)
  local ok = nitro.writeFile(SHARE_DIR .. tr.name, fullData)
  if ok then
    refreshLocalFiles(nitro)
    addLog("Salvo em " .. SHARE_DIR .. tr.name .. " (" .. #fullData .. "B)")
  else
    addLog("Falha ao salvar " .. tr.name)
  end
end

local function handleListR(rest)
  local idxStr, name, sizeStr = splitThree(rest)
  local idx = tonumber(idxStr)
  if idx == 0 then
    state.remoteFiles = {}
    state.selectedIdx = 1
    state.scroll = 0
    return
  end
  if idx == 1 then
    state.remoteFiles = {}
  end
  if isValidName(name) then
    local sz = tonumber(sizeStr) or 0
    table.insert(state.remoteFiles, { name = name, size = math.max(0, math.floor(sz)) })
  end
end

local function getBox(self)
  local x0 = tonumber(self and self.x) or 1
  local y0 = tonumber(self and self.y) or 1
  local w = tonumber(self and self.w) or 60
  local h = tonumber(self and self.h) or 20
  return x0, y0, w, h
end

local function beginInput(mode)
  state.inputMode = mode
  if mode == "server" then
    state.inputBuf = state.serverAddr
  elseif mode == "pass" then
    state.inputBuf = state.password
  elseif mode == "put" then
    state.inputBuf = ""
  end
end

local function commitInput(nitro)
  local mode = state.inputMode
  local val = state.inputBuf
  state.inputMode = nil
  state.inputBuf = ""

  if mode == "server" then
    state.serverAddr = val:gsub("^%s+", ""):gsub("%s+$", "")
    addLog("Servidor: " .. (state.serverAddr ~= "" and state.serverAddr:sub(1, 16) or "nenhum"))
  elseif mode == "pass" then
    state.password = val
    addLog(state.password == "" and "Senha limpa" or "Senha definida")
  elseif mode == "put" then
    if val ~= "" then
      requestPut(nitro, val)
    end
  end
end

return {
  title = "Cliente NAS",
  w = 60,
  h = 20,

  body = function(self, nitro)
    init(nitro)
    local c = nitro.colors
    local x0, y0, w, h = getBox(self)
    state.lastBox = { x0 = x0, y0 = y0, w = w, h = h }

    local innerW = math.max(24, w - 2)
    local innerH = math.max(12, h - 1)
    nitro.rect(x0 + 1, y0 + 1, innerW, innerH, c.bg)

    nitro.rect(x0 + 1, y0 + 1, innerW, 3, c.panel)
    local netStatus = state.hasCard and (state.portOpen and "Wi-Fi: ON" or "Wi-Fi: BLOQ") or "Wi-Fi: OFF"
    local netCol = (state.hasCard and state.portOpen) and c.ok or c.err
    nitro.put(x0 + 2, y0 + 1, "ID: " .. state.clientId:sub(1, 14), c.text, c.panel, 19)
    nitro.put(x0 + 22, y0 + 1, netStatus, netCol, c.panel, 13)
    nitro.put(x0 + 36, y0 + 1, "[Srv]", c.bg, c.accent, 6)
    nitro.put(x0 + 43, y0 + 1, "[Senha]", c.bg, c.warn, 8)
    nitro.put(x0 + 52, y0 + 1, "[F5]", c.bg, c.ok, 5)

    if state.inputMode then
      local lbl = "Valor: "
      if state.inputMode == "server" then
        lbl = "ID/End Servidor: "
      elseif state.inputMode == "pass" then
        lbl = "Senha: "
      elseif state.inputMode == "put" then
        lbl = "Arq em " .. SHARE_DIR .. ": "
      end
      nitro.put(x0 + 2, y0 + 2, lbl .. state.inputBuf .. "_", c.accent, c.panel, innerW - 2)
    else
      local srvShow = state.serverAddr ~= "" and state.serverAddr:sub(1, 18) or "(nao definido)"
      local pwdShow = state.password ~= "" and ("*" .. #state.password) or "aberta"
      nitro.put(x0 + 2, y0 + 2, "Srv: " .. srvShow, c.text, c.panel, 25)
      nitro.put(x0 + 28, y0 + 2, "Pwd: " .. pwdShow, c.dim, c.panel, 12)
      nitro.put(x0 + 41, y0 + 2, "[Baixar]", c.bg, c.accent, 9)
      nitro.put(x0 + 51, y0 + 2, "[Enviar]", c.bg, c.ok, 9)
    end

    nitro.put(x0 + 2, y0 + 3, "Pasta local: " .. SHARE_DIR .. " | Remotos: " .. #state.remoteFiles, c.dim, c.panel, innerW - 2)

    nitro.put(x0 + 2, y0 + 5, "ARQUIVOS NO SERVIDOR (Setas: mover)", c.accent, c.bg, innerW - 2)
    nitro.rect(x0 + 2, y0 + 6, innerW - 2, 5, c.panel)
    if #state.remoteFiles == 0 then
      nitro.put(x0 + 3, y0 + 7, "(Lista vazia - toque [F5] ou [Srv] para conectar)", c.dim, c.panel, innerW - 4)
    else
      for row = 0, 4 do
        local idx = state.scroll + row + 1
        local item = state.remoteFiles[idx]
        if item then
          local isSel = (idx == state.selectedIdx)
          local fg = isSel and c.bg or c.text
          local bg = isSel and c.accent or c.panel
          nitro.rect(x0 + 2, y0 + 6 + row, innerW - 2, 1, bg)
          local prefix = isSel and "> " or "  "
          nitro.put(x0 + 3, y0 + 6 + row, prefix .. item.name, fg, bg, math.max(8, innerW - 14))
          nitro.put(x0 + innerW - 10, y0 + 6 + row, string.format("%6d B", item.size), fg, bg, 10)
        end
      end
    end

    nitro.put(x0 + 2, y0 + 12, "LOG DE EVENTOS", c.accent, c.bg, innerW - 2)
    local maxLogRows = math.max(2, (y0 + innerH) - (y0 + 13) + 1)
    nitro.rect(x0 + 2, y0 + 13, innerW - 2, maxLogRows, c.panel)
    if #state.logs == 0 then
      nitro.put(x0 + 3, y0 + 14, "Pronto. Configure o servidor e pressione F5.", c.dim, c.panel, innerW - 4)
    else
      for row = 0, maxLogRows - 1 do
        local entry = state.logs[row + 1]
        if entry then
          nitro.put(x0 + 3, y0 + 13 + row, "> " .. entry, c.text, c.panel, innerW - 4)
        end
      end
    end
  end,

  onKey = function(self, char, code, nitro)
    if state.inputMode then
      if char == 28 or code == 28 then
        commitInput(nitro)
        return true
      elseif char == 1 or code == 1 then
        state.inputMode = nil
        state.inputBuf = ""
        addLog("Entrada cancelada")
        return true
      elseif char == 14 or code == 14 then
        if #state.inputBuf > 0 then
          state.inputBuf = state.inputBuf:sub(1, -2)
        end
        return true
      elseif type(char) == "number" and char >= 32 and char <= 126 then
        local ch = string.char(char)
        if ch ~= "|" and #state.inputBuf < 40 then
          state.inputBuf = state.inputBuf .. ch
          return true
        end
      end
      return true
    end

    if code == 1 then
      return false
    elseif code == 63 then
      requestList(nitro)
      return true
    elseif code == 200 then
      if state.selectedIdx > 1 then
        state.selectedIdx = state.selectedIdx - 1
        if state.selectedIdx < state.scroll + 1 then
          state.scroll = state.selectedIdx - 1
        end
      end
      return true
    elseif code == 208 then
      if state.selectedIdx < #state.remoteFiles then
        state.selectedIdx = state.selectedIdx + 1
        if state.selectedIdx > state.scroll + 5 then
          state.scroll = state.selectedIdx - 5
        end
      end
      return true
    elseif char == 28 or code == 28 then
      local sel = state.remoteFiles[state.selectedIdx]
      if sel then
        requestGet(nitro, sel.name)
      else
        requestList(nitro)
      end
      return true
    end
    return false
  end,

  onTouch = function(self, x, y, nitro)
    local box = state.lastBox or {}
    local x0 = box.x0 or tonumber(self and self.x) or 1
    local y0 = box.y0 or tonumber(self and self.y) or 1

    if y == y0 + 1 then
      if x >= x0 + 36 and x <= x0 + 41 then
        beginInput("server")
        return true
      elseif x >= x0 + 43 and x <= x0 + 50 then
        beginInput("pass")
        return true
      elseif x >= x0 + 52 and x <= x0 + 57 then
        requestList(nitro)
        return true
      end
    elseif y == y0 + 2 and not state.inputMode then
      if x >= x0 + 41 and x <= x0 + 49 then
        local sel = state.remoteFiles[state.selectedIdx]
        if sel then
          requestGet(nitro, sel.name)
        else
          addLog("Selecione um arquivo na lista")
        end
        return true
      elseif x >= x0 + 51 and x <= x0 + 59 then
        beginInput("put")
        return true
      end
    elseif y >= y0 + 6 and y <= y0 + 10 then
      local clickedIdx = state.scroll + (y - (y0 + 6)) + 1
      if state.remoteFiles[clickedIdx] then
        state.selectedIdx = clickedIdx
        return true
      end
    end
    return false
  end,

  onModem = function(self, addr, port, dist, msg, nitro)
    if port ~= PORT or type(msg) ~= "string" or type(addr) ~= "string" then
      return
    end
    if state.serverAddr ~= "" and addr ~= state.serverAddr then
      return
    end
    if state.serverAddr == "" then
      state.serverAddr = addr
    end

    local cmd, rest = splitCmd(msg)

    if cmd == "OK" then
      addLog("Servidor OK: " .. tostring(rest or ""))
      if rest == "autenticado" and state.pendingAction then
        local act = state.pendingAction
        state.pendingAction = nil
        if act == "LIST" then
          state.remoteFiles = {}
          sendToServer(nitro, "LIST|")
        elseif type(act) == "table" and act.type == "GET" then
          sendToServer(nitro, "GET|" .. act.name)
        elseif type(act) == "table" and act.type == "PUT" then
          sendLocalFile(nitro, act.name)
        end
      end
    elseif cmd == "ERR" then
      state.pendingAction = nil
      addLog("Erro servidor: " .. tostring(rest or "desconhecido"))
    elseif cmd == "LISTR" then
      handleListR(rest)
    elseif cmd == "FILE" then
      handleFileHeader(rest)
    elseif cmd == "CHUNK" then
      handleChunk(rest)
    elseif cmd == "END" then
      handleEnd(nitro, rest)
    end
  end
}
