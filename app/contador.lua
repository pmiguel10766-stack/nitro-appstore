-- name: Contador
-- desc: App de exemplo para o Nitro OS (clique em + e -)
local count = 0

return {
  title = "Contador",
  w = 34,
  h = 10,
  body = function(win, nitro)
    local c = nitro.colors
    nitro.put(win.x + 3, win.y + 2, "Contagem: " .. count .. "   ", c.text, c.panel)
    nitro.put(win.x + 3, win.y + 4, " + ", c.bg, c.accent)
    nitro.put(win.x + 8, win.y + 4, " - ", c.bg, c.accent)
    nitro.put(win.x + 3, win.y + 6, "Clique nos botoes ou use + e -", c.dim, c.panel, win.w - 6)
    nitro.put(win.x + 3, win.y + 7, "Esc fecha a janela", c.dim, c.panel, win.w - 6)
  end,
  onTouch = function(win, x, y, nitro)
    if y == win.y + 4 then
      if x >= win.x + 3 and x < win.x + 6 then
        count = count + 1
        return true
      elseif x >= win.x + 8 and x < win.x + 11 then
        count = count - 1
        return true
      end
    end
    return false
  end,
  onKey = function(win, char, code, nitro)
    if char == 43 or char == 61 then
      count = count + 1
      return true
    elseif char == 45 then
      count = count - 1
      return true
    end
    return false
  end,
}
