-- Mini-Jogo de Brute-Force / Hacker para o Nitro OS
local component = require("component")
local computer = require("computer")
local gpu = component.gpu

-- Cores do terminal
gpu.setForeground(0x00FF00) -- Verde hacker
gpu.setBackground(0x000000) -- Fundo preto
term.clear()

print("========================================")
print("   NITRO OS - SECURE SHELL HACK v1.0   ")
print("========================================")
print("Aceda ao terminal remoto antes que o")
print("antivírus detete a intrusão na RAM.\n")

-- Gerar uma senha aleatória simples (ex: 4 dígitos hexadecimales)
math.randomseed(computer.uptime())
local senha_secreta = string.format("%04X", math.random(0, 65535))
local tentativas = 4

print("[INFO] Alvo fixado. Senha encriptada gerada.")
print("[INFO] Tens " .. tentativas .. " tentativas para quebrar o firewall.\n")

while tentativas > 0 do
    io.write("Introduza o código (Ex: A3F1): ")
    local input = io.read()
    
    -- Converter para maiúsculas para comparar
    input = string.upper(input or "")
    
    if input == senha_secreta then
        print("\n[SUCESSO] Acesso concedido! Firewall neutralizado.")
        print("[!] Desbloqueaste dados confidenciais do sistema.")
        return
    else
        tentativas = tentativas - 1
        if tentativas > 0 then
            print("[ALERTA] Código incorreto! Restam " .. tentativas .. " tentativas.\n")
        else
            print("\n[ERRO CRÍTICO] Acesso bloqueado! O antivírus detetou a invasão.")
        end
    end
end
