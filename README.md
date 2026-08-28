# 🚀 Painel SSH + Xray - VPS Manager

Painel de gerenciamento **interativo em Bash** para administrar SSH e Xray (VLESS/VMess/Trojan) diretamente da VPS, sem necessidade de interface web.

Desenvolvido para funcionar em **Debian/Ubuntu** (e derivados) e também RHEL/CentOS.

---

## 📦 Instalação

```bash
git clone https://github.com/Alefsousa5/script2.git
cd script2
chmod +x install.sh
sudo bash install.sh
```

Após instalado, basta rodar:
```bash
sudo painel
```

Ou diretamente sem instalar:
```bash
sudo bash painel.sh
```

---

## 🧭 Funcionalidades

### 🛡️ Gerenciamento SSH
- Criar/remover/listar usuários SSH
- Gerar senha aleatória automaticamente
- Expiração de contas (dias)
- Alterar porta SSH (com backup de segurança)
- Bloquear/desbloquear usuários
- Desabilitar login do root por senha (segurança)
- Reiniciar o serviço SSH
- Gerar par de chaves ed25519 para um usuário

### ⚡ Gerenciamento Xray
- Instalação do Xray (via script oficial)
- Instalação com configuração básica automática (VLESS + TLS, VMess, Trojan)
- Criar contas **VLESS**, **VMess** e **Trojan**
- Listar todas as contas com etiqueta (operadora: TIM/Vivo/Claro) e validade
- Remover contas
- Gerar **link de conexão** e **QR Code** (para importar no app direto)
- Reiniciar/parar Xray
- Validação de configuração antes de reiniciar
- Backup e restauração da config
- Portas em uso e status do serviço

### 💻 Informações do Sistema
- SO, kernel, arquitetura, hostname
- IP público/privado, uptime
- Uso de CPU, RAM, swap, disco
- Interfaces de rede e tráfego total (download/upload desde o boot)
- Load average
- Status dos serviços principais (SSH, Xray, fail2ban, nginx, etc)

### 👁️ Monitoramento
- Conexões SSH ativas
- Conexões Xray ativas
- Sockets abertos (portas em listen)
- Últimos logins e sessões ativas
- Tentativas de acesso falhas (auth.log)
- Tráfego em tempo real (atualiza a cada 2s)
- Top processos por CPU/RAM

### 🛠️ Ferramentas Úteis
- Speedtest (teste de velocidade)
- Ping para destinos comuns (Google, Cloudflare)
- Status do firewall (UFW/iptables)
- Liberar portas no firewall
- **Backup completo** (SSH + Xray + lista de usuários)
- Limpeza de logs
- Atualização do sistema (apt update/upgrade)
- Reboot/shutdown da VPS
- Alterar senha do root
- Verificar IPs
- **Limpeza automática de contas Xray e SSH expiradas**

### 📋 Logs
- Acesso e erro do Xray
- Logs de autenticação SSH
- Logs do systemd do Xray
- Acompanhamento em tempo real (`tail -f`)

---

## 📁 Estrutura

```
script2/
├── painel.sh            # Entrada principal
├── install.sh           # Instalador
├── README.md
└── modules/
    ├── colors.sh        # Cores e helpers de mensagem
    ├── common.sh        # Funções utilitárias, detecção de IP/portas
    ├── menu.sh          # Menu principal
    ├── ssh_manager.sh   # Gerenciamento de SSH
    ├── xray_manager.sh  # Gerenciamento de Xray (VLESS/VMess/Trojan)
    ├── system_info.sh   # Info do sistema
    ├── monitor.sh       # Monitor de conexões
    └── utils.sh         # Ferramentas e menu de logs
```

---

## ⚠️ Observações importantes

1. **Execute sempre como root** (`sudo painel`).
2. Ao **alterar a porta SSH**, o script avisa para testar o acesso em outra sessão antes de fechar a atual — é uma proteção contra travamento da VPS.
3. O Xray é configurado com um **certificado TLS auto-assinado** por padrão. Para uso em produção com domínio real, recomenda-se substituir pelo Let's Encrypt.
4. Os links VLESS/Trojan gerados usam o IP como SNI. Edite manualmente se precisar usar um domínio.
5. Contas expiradas do Xray são removidas na opção **"Limpeza de contas expiradas"** do menu Ferramentas.

---

## 🧪 Testado em
- Debian 11/12
- Ubuntu 20.04 / 22.04 / 24.04

---

## 📝 Licença
Uso livre para fins pessoais e educacionais.
