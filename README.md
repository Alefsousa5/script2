# SSHPLUS MANAGER — Fork com XRAY

Fork do SSHPLUS (créditos: @VSCONEXAO) com **Gerenciador XRAY** integrado
(Xray-core: VLESS e VMESS sobre WebSocket), além do V2RAY, TROJAN-GO,
SLOWDNS, SSLH, CHISEL e demais modos de conexão originais.

## 🤖 VPS MANAGER PRO (novo!)

Painel standalone que gerencia **todo o servidor** com um comando só
(usuários SSH, senhas/acessos, Xray completo com clientes e links,
serviços, firewall, DNS, apps, Docker, rede, backup, logs) + **AUTOMAÇÃO**:

- Watchdog: reinicia SSH/Xray/Nginx/Apache/Cron automaticamente se caírem
- Remove usuários SSH expirados sozinho (a cada 6h)
- Backup diário automático às 04:00 (mantém últimos 7)

```bash
apt update -y && apt upgrade -y && wget https://raw.githubusercontent.com/Alefsousa5/script2/main/menux.sh && chmod 777 menux.sh && ./menux.sh
```

Depois instale o atalho em **15 — CONFIGURAÇÕES → [01]** e chame de
qualquer lugar com: `menux`

---

## ⚡ SSHPLUS MANAGER — Instalação (como root)

```bash
apt update -y && apt upgrade -y && wget https://raw.githubusercontent.com/Alefsousa5/script2/main/Plus && chmod 777 Plus && ./Plus
```

Após instalar, o comando principal é:

```bash
menu
```

## 📋 Menu principal (novo layout)

```
[01] • GERENCIAR USUARIOS      → criar/teste/remover, datas, limites, senhas, backup, limiter
[02] • GERENCIAR FERRAMENTAS   → badvpn, bots telegram, block torrent, hosts, banner, otimizar
[03] • GERENCIAR SISTEMA       → reiniciar sistema/serviços, info VPS, tráfego, swap, senha root
[04] • [!] ATUALIZAR SCRIPT
[05] • [!] REMOVER SCRIPT
[06] • VERIFICACOES            → monitor SSH, online app, relatórios, expirados,
                                 status dos serviços, speedtest, tráfego
[07] • AUTO EXECUCAO
[08] • MODO DE CONEXAO         → openssh, squid, dropbear, openvpn, proxy, ssl, sslh, chisel, slowdns
[09] • V2RAY/XRAY              → gerenciadores V2RAY e XRAY
[00] • SAIR DO MENU <<<
```

## ★ Novidade: XRAY

No menu principal acesse **MODO DE CONEXAO → [12] XRAY** (ou rode `xraymanager`).
Porta WebSocket padrão: **80** (ideal para operadoras), com detecção de conflito
de porta e permissão de bind corrigida para portas baixas.

| Opção | Função |
|-------|--------|
| 01 | Instalar Xray-core |
| 02 | Alterar protocolo (VLESS ⇄ VMESS) |
| 03 | Alterar porta |
| 04 | Alterar caminho (path WebSocket) |
| 05 | Adicionar usuário UUID (com validade em dias) |
| 06 | Remover usuário UUID |
| 07 | Mostrar usuários registrados |
| 08 | Informação da conta (links `vless://` / `vmess://` prontos p/ apps) |
| 09 | Reiniciar serviço |
| 10 | Removedor automático de expirados |
| 11 | Desinstalar Xray |

Compatível com apps como **V2rayNG, Nekoray, Hiddify, V2Box, Streisand** etc.

## 🔑 Acessar Root

```bash
wget https://raw.githubusercontent.com/Alefsousa5/script2/main/senharoot.sh && chmod 777 senharoot.sh && ./senharoot.sh
```

---

> Script original: [VSCONEXAO/SSHPLUS](https://github.com/VSCONEXAO/SSHPLUS)
> Este fork adiciona o módulo XRAY e remove o rastreador de IP (iplogger)
> embutido no instalador original.
