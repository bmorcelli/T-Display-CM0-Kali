# Ethernet do CM0 — configuração validada em 11/11/2026

O RTL8152B integrado funciona usando o controlador original `dwc_otg` com
`dwc_otg.speed=1` na única linha de `/boot/firmware/cmdline.txt`. As overlays
`dwc2,dr_mode=host` e `cm0-usb-full-speed` não devem estar ativas neste CM0.
Preserve todos os argumentos existentes, especialmente `root=`.

Para reaplicar após reinstalar a imagem, execute neste aparelho:

```sh
sudo bash ethernet_fix/install.sh
sudo reboot
```

O script cria backup em `/var/backups/cm0-ethernet-*`, usa DHCP, configura um
MAC local estável derivado do serial da CPU e prioriza a Ethernet. Ele não
reinicia automaticamente. Este script é separado do instalador geral dos
recursos; execute-o depois do instalador geral se estiver preparando outra imagem.

## Resultado observado

- Kernel: `6.12.34+rpt-rpi-v7`, Kali ARMv7.
- MAC deste aparelho: `02:b8:27:b5:c4:20`.
- IPv4 obtido por DHCP: `192.168.3.246` (pode mudar conforme o roteador).
- Wi-Fi desligado durante a validação.
- 30/30 respostas do gateway; 5/5 respostas de `1.1.1.1`; HTTPS HTTP 200.
- Upload de 8 MiB: 7,617 Mb/s. Download de 8 MiB: 8,354 Mb/s.
- SHA256 do conteúdo aleatório conferido nos dois sentidos:
  `783c7f1721c4efc50af84edfe3f25b39465f760906408c8a48ae9eae4c6dc09b`.
- Após outro reboot, todos os testes foram repetidos com sucesso: 8 MiB em
  cada sentido, 7,467 e 8,415 Mb/s, com SHA256
  `da59fb2c692d7ee9d4524229f1c99937aa661e69f108a26740d65b7546fb262c`.

O link RJ45 negocia 100 Mb/s full duplex, mas o USB interno está limitado a
12 Mb/s. Portanto não se deve esperar taxa útil de 100 Mb/s. Em 480 Mb/s,
tanto `dwc_otg` quanto `dwc2` apresentaram falhas de transferência/recepção;
com `dwc2`, usbmon mostrou URBs RX terminando com `-71` (`EPROTO`). O teste
a 10 Mb/s no RJ45 não corrigiu isso. A evidência aponta para o caminho USB
em alta velocidade, sem identificar com certeza o componente físico responsável.

O MAC de fábrica continua zerado. O NetworkManager aplica o MAC estável
quando ativa a conexão; por isso a mensagem inicial de MAC inválido pode
continuar no boot. Não houve gravação de EEPROM. O contador de hardware
`rx_missed` cresceu sob carga, apesar das transferências completas e íntegras;
a solução fornece conectividade funcional com limite de desempenho.

Não desconecte/reconecte o controlador USB inteiro pelo sysfs: o caminho de
remoção do `dwc_otg` neste kernel já provocou uma falha do kernel durante o
diagnóstico. Aplique alterações do controlador por reboot.

Para reverter, restaure `config.txt`, `cmdline.txt` e os perfis de rede do
backup correspondente, execute `sudo nmcli connection reload` e reinicie.
