# Drivers e Ethernet — CM0, 11/11/2026

Os módulos compilados estão em `lilygo_resources/drivers/` e o overlay em
`lilygo_resources/dtbo/`. Foram instalados no aparelho e carregados por reboot.
Kernel de destino: **6.12.34+rpt-rpi-v7, ARMv7**. Não use estes módulos em
outro kernel sem recompilar contra os headers correspondentes.

| Artefato | Alteração |
| --- | --- |
| `drivers/es8389.ko` | Equilibra referências do clock; evita desabilitar o clock crítico sem possuir referência. |
| `drivers/bq25890_charger.ko` | Descreve a ausência prevista de IRQ; mantém avisos de falhas reais. Não altera parâmetros de carga. |
| `drivers/goodix_berlin_core.ko` | Recupera o fonte ausente e relê eventos com checksum inválido até três vezes; descarta eventos que continuam inválidos. |
| `drivers/rtc-ds1307.ko` | Adicionado em 12/11: corrige a conversão do dia da semana no Epson RX8130. Veja `RTC-VALIDATION.md`. |
| `dtbo/panel_rm69a10_amoled.dtbo` | Flags open-drain corretas e atraso I²C de 5 µs, aproximadamente 100 kHz. |

Fontes em `src/cmo_drivers/` e `src/dts/`. Compilação com GCC ARM 12.4,
headers exatos e `W=1 KCFLAGS=-Werror`. Teste das funções de clock com 100
ciclos, chamadas repetidas, falha de habilitação e limpeza: aprovado.
Overlay compilado e aplicado ao DTB base para conferir os pinos/flags.
Os avisos de clock crítico e de flags open-drain não reapareceram nos boots
de validação. A reprodução de áudio silencioso completou com sucesso.
Os contadores novos do touch estavam em zero nos boots finais; falta um
teste físico de toque após a instalação desse último módulo para medir
a recuperação sob interação. Erros I²C intermitentes de outros componentes
observados anteriormente não foram ocultados nem considerados resolvidos.

## Ethernet funcionando

A solução aplicada utiliza o controlador original **dwc_otg** com
**dwc_otg.speed=1** em `/boot/firmware/cmdline.txt`. A overlay `dwc2` foi
desativada para este CM0. O hub e o RTL8152B enumeram a **12 Mb/s**.
Não foi necessário recompilar o r8152 para obter conectividade.

O MAC de fábrica é zerado. O perfil NetworkManager `CM0-Ethernet` aplica
`02:b8:27:b5:c4:20`, estável e local, usa DHCP e prioriza Ethernet sobre
Wi-Fi. O endereço obtido foi **192.168.3.246**, sujeito à concessão DHCP.

Validação com o Wi-Fi desligado:

- 30/30 pings ao gateway e 5/5 a `1.1.1.1`.
- HTTPS via `curl --interface eth0`: HTTP 200.
- Transferência SSH de 8 MiB em cada sentido, com SHA256 conferido.
- Taxas observadas no primeiro teste: 7,617 Mb/s recebendo no CM0 e
  8,354 Mb/s enviando do CM0.
- Após outro reboot, repetidos com sucesso os mesmos testes: 8 MiB em cada
  sentido, hashes conferidos, 7,467 Mb/s recebendo e 8,415 Mb/s enviando;
  30/30 pings ao gateway, 5/5 à internet e HTTPS HTTP 200.

O RJ45 continua negociando 100 Mb/s full duplex; o USB limita a taxa útil.
Em 480 Mb/s, a captura usbmon mostrou URBs RX com `-71`/`EPROTO` e a
recepção estagnava. A causa física exata no caminho USB não foi determinada.
O contador de hardware `rx_missed` cresce sob carga; as transferências
verificadas terminaram íntegras. Esta é uma solução funcional com restrição
de desempenho, sem afirmar reparo do modo USB de alta velocidade.

Instruções e script para reaplicar: `lilygo_resources/ethernet_fix/README.md`.
O script é separado do instalador geral e deve ser executado depois dele.
O instalador geral já coleta os módulos e overlays nos diretórios acima.
Não há EEPROM reprogramada nem configuração de IP estático.

## Registros

Capturas completas, backups e pacote de drivers estão em
`C:\Users\Bernardo\Downloads\CM0-recovery-20261111`.
Os logs finais também são copiados para `diagnostics/` nesta pasta.
Backups de configuração de rede ficam fora deste pacote para não distribuir
credenciais Wi-Fi. As senhas de acesso não estão incluídas neste relatório.

Consulte `SHA256SUMS-driver-fixes` para verificar os binários corrigidos.
