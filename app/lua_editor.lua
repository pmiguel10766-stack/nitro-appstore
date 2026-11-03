-- name: Editor Lua
-- desc: Editor de codigo Lua para Nitro OS

local component = require("component")
local gpu = component.gpu

local lines = {
  "-- Bem-vindo ao Editor Lua do Nitro OS",
  "local nitro = ...",
  "print('A executar codigo nativo...')",
}
local cursorY = 1

return {
  title = "Editor Lua", w = 58, h = 16,

  body = function(self, nitro)
    -- Desenha a área de texto linha a linha usando gpu diretamente
    for i = 1, self.h - 3 do
      local textLine = lines[i] or ""
      if #textLine > self.w - 4 then
        textLine = textLine:sub(1, self.w - 5) .. ">"
      end
      gpu.set(2, i + 1, string.rep(" ", self.w - 2))
      gpu.set(2, i + 1, textLine)
    end

    -- Barra de status inferior
    gpu.set(2, self.h - 1, string.rep("-", self.w - 2))
    gpu.set(2, self.h, " Linha: " .. cursorY .. " | [ESC] Fechar")
  end,

  onKey = function(self, char, code, nitro)
    if code == 1 then -- Tecla ESC fecha a janela
      return true
    elseif code == 200 then -- Seta para cima
      cursorY = math.max(1, cursorY - 1)
      return true
    elseif code == 208 then -- Seta para baixo
      cursorY = math.min(#lines, cursorY + 1)
      return true
    elseif char > 0 then
      local ch = string.char(char)
      lines[cursorY] = (lines[cursorY] or "") .. ch
      return true
    end
    return false
  end,

  onTouch = function(self, x, y, nitro)
    if y > 1 and y < self.h - 2 then
      local targetLine = y - 1
      if targetLine <= #lines + 1 then
        cursorY = targetLine
        if not lines[cursorY] then lines[cursorY] = "" end
      end
    end
    return true
  end
}
