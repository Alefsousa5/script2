# script2

Script Xray rodando para as operadoras (foco inicial: TIM).

## O que o script faz

O `install.sh` instala o **Xray** na VPS e já deixa tudo pronto:

- Baixa a versão mais recente do Xray compatível com a arquitetura da VPS.
- Cria o usuário `xray` e os diretórios de configuração e logs.
- Gera um `config.json` com **2 inbounds**:
  - TCP na porta principal (VLESS ou VMess).
  - mKCP na porta `principal + 1` (ajuda em redes que limitam TCP).
- Cria e habilita o serviço **systemd** (`xray.service`).
- Exibe no final o IP, a porta e o **UUID** gerado para conectar.

## Como usar

Envie o script para a VPS e execute como root:

```bash
# copiar para a VPS
scp install.sh usuario@IP_DA_VPS:/tmp/

# conectar e rodar
ssh usuario@IP_DA_VPS
sudo bash /tmp/install.sh
```

Ou na própria VPS, se já estiver no repositório:

```bash
sudo bash install.sh
```

### Opções

| Opção | Descrição | Padrão |
|---|---|---|
| `--port` | Porta dos inbounds | `8080` |
| `--uuid` | UUID a usar nos inbounds | gerado automaticamente |
| `--protocol` | `vless` ou `vmess` | `vless` |
| `--no-color` | Desativa as cores na saída | — |
| `-h, --help` | Mostra a ajuda | — |

Exemplos:

```bash
sudo bash install.sh
sudo bash install.sh --port 443
sudo bash install.sh --port 8080 --uuid "00000000-0000-0000-0000-000000000000"
sudo bash install.sh --port 8443 --protocol vmess
```

## Comandos úteis após a instalação

```bash
systemctl status xray     # status
systemctl restart xray    # reiniciar
journalctl -u xray -f     # acompanhar logs
cat /usr/local/etc/xray/config.json   # ver a config
```

## Avisos

- As portas **principal** e **principal + 1** precisam estar liberadas no firewall da VPS (`ufw`, `iptables`, painel da provedora, etc.).
- Em redes de operadora (TIM), pode ser necessário testar portas diferentes até achar uma que não seja bloqueada.
