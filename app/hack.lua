-- Mini-Jogo de Brute-Force / Hacker para o Nitro OS (pt-BR)
return {
    title = "Hacker Brute-Force", 
    w = 52, 
    h = 13,
  body = function(self, nitro)
        -- Inicializa o jogo na primeira execução
        if not self.senha_secreta then
            -- Usa o uptime do computador como semente segura no OpenComputers
            math.randomseed(math.floor(computer.uptime() * 1000000))
            
            -- Sorteia um valor entre 0 e 255 (00 a FF em hexadecimal) para ser jogável
            self.alvo_num = math.random(0, 255)
            self.senha_secreta = string.format("%02X", self.alvo_num)
            
            self.tentativas = 4
            self.mensagem = "Insira um codigo de 2 digitos (Ex: 4F) e pressione Enter."
            self.input_text = ""
            self.venceu = false
            self.perdeu = false
        end
        
        -- Desenhar interface na janela do Nitro OS
        nitro.put(self.x + 2, self.y + 2, "=== NITRO SECURE SHELL HACK ===")
        nitro.put(self.x + 2, self.y + 3, "Alvo: Terminal Remoto (Firewall Ativo)")
        nitro.put(self.x + 2, self.y + 4, "Tentativas restantes: " .. tostring(self.tentativas))
        
        -- Campo de entrada
        nitro.put(self.x + 2, self.y + 7, "Codigo: [ " .. self.input_text .. "_ ]")
        
        -- Mensagem de status ou dica
        nitro.put(self.x + 2, self.y + 10, tostring(self.mensagem))
    end,
    
    onKey = function(self, char, code, nitro)
        if self.venceu or self.perdeu then
            return false
        end
        
        -- Código 28 é Enter
        if code == 28 then
            local limpo = string.upper(self.input_text):gsub("%s", "")
            if #limpo < 2 then
                self.mensagem = "Digite 2 digitos hexadecimais!"
                return true
            end
            
            local tentativa_num = tonumber(limpo, 16)
            if not tentativa_num then
                self.mensagem = "Valor hexadecimal invalido (Use 0-9, A-F)."
                self.input_text = ""
                return true
            end
            
            if limpo == self.senha_secreta then
                self.venceu = true
                self.mensagem = "[SUCESSO] Acesso concedido! Firewall neutralizado."
            else
                self.tentativas = self.tentativas - 1
                if self.tentativas > 0 then
                    if tentativa_num < self.alvo_num then
                        self.mensagem = "[ALERTA] Incorreto! O codigo e MAIOR (^)."
                    else
                        self.mensagem = "[ALERTA] Incorreto! O codigo e MENOR (v)."
                    end
                    self.input_text = ""
                else
                    self.perdeu = true
                    self.mensagem = "[ERRO] Acesso bloqueado pelo antivirus!"
                end
            end
            return true
            
        -- Código 14 é Backspace
        elseif code == 14 then
            if #self.input_text > 0 then
                self.input_text = string.sub(self.input_text, 1, #self.input_text - 1)
            end
            return true
            
        -- Captura caracteres alfanuméricos válidos para Hex (0-9, A-F, a-f)
        elseif char then
            local c = string.char(char):upper()
            if c:match("[0-9A-F]") and #self.input_text < 2 then
                self.input_text = self.input_text .. c
            end
            return true
        end
        
        return false
    end
}
