# SSHPLUS MANAGER — Fork com XRAY

Fork do SSHPLUS (créditos: @VSCONEXAO) com **Gerenciador XRAY** integrado
(Xray-core: VLESS e VMESS sobre WebSocket), além do V2RAY, TROJAN-GO,
SLOWDNS, SSLH, CHISEL e demais modos de conexão originais.

## ⚡ Instalação (como root)

```bash
apt update -y && apt upgrade -y && wget https://raw.githubusercontent.com/Alefsousa5/script2/main/Plus && chmod 777 Plus && ./Plus
```

Após instalar, o comando principal é:

```bash
menu
```

## ★ Novidade: XRAY

No menu principal acesse **MODO DE CONEXAO → [12] XRAY** (ou rode `xraymanager`):

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
