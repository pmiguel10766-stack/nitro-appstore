-- Mini-Jogo de Brute-Force / Hacker para o Nitro OS (pt-BR)
return {
    title = "Hacker Brute-Force", 
    w = 52, 
    h = 13,
    
    body = function(self, nitro)
        -- Inicializa o jogo na primeira execução usando a API nitro
        if not self.senha_secreta then
            -- Usa nitro.uptime() para semente segura no ambiente restrito
            math.randomseed(math.floor(nitro.uptime() * 1000000))
            
            -- Sorteia um valor entre 0 e 255 (00 a FF em hexadecimal)
            self.alvo_num = math.random(0, 255)
            self.senha_secreta = string.format("%02X", self.alvo_num)
            
            self.tentativas = 4
            self.mensagem = "Insira um código de 2 dígitos (Ex: 4F) e pressione Enter."
            self.input_text = ""
            self.venceu = false
            self.perdeu = false
        end
        
        -- Desenhar interface na janela do Nitro OS
        nitro.put(self.x + 2, self.y + 2, "=== NITRO SECURE SHELL HACK ===")
        nitro.put(self.x + 2, self.y + 3, "Alvo: Terminal Remoto (Firewall Ativo)")
        nitro.put(self.x + 2, self.y + 4, "Tentativas restantes: " .. tostring(self.tentativas))
        
        -- Campo de entrada
        nitro.put(self.x + 2, self.y + 7, "Código: [ " .. self.input_text .. "_ ]")
        
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
                self.mensagem = "Digite 2 dígitos hexadecimais!"
                return true
            end
            
            local tentativa_num = tonumber(limpo, 16)
            if not tentativa_num then
                self.mensagem = "Valor hexadecimal inválido (Use 0-9, A-F)."
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
                        self.mensagem = "[ALERTA] Incorreto! O código é MAIOR (^)."
                    else
                        self.mensagem = "[ALERTA] Incorreto! O código é MENOR (v)."
                    end
                    self.input_text = ""
                else
                    self.perdeu = true
                    self.mensagem = "[ERRO] Acesso bloqueado pelo antivírus!"
                end
            end
            return true
            
        -- Código 14 é Backspace
        elseif code == 14 then
            if #self.input_text > 0 then
                self.input_text = string.sub(self.input_text, 1, #self.input_text - 1)
            end
            return true
            
        -- Captura caracteres imprimíveis e filtra apenas o necessário para Hex
        elseif char and char >= 32 and char <= 126 then
            local c = string.char(char):upper()
            if c:match("[0-9A-F]") and #self.input_text < 2 then
                self.input_text = self.input_text .. c
            end
            return true
        end
        
        return false
    end
}
