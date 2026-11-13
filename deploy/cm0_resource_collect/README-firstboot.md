# Primeiro boot: swap de 1 GiB

Copie também `setup_swap.sh` para a partição de boot, ao lado de
`firstrun.sh`, `firstrun.txt` e da pasta `lilygo_resources`.
Prepare o `cmdline.txt` com o procedimento existente.

O serviço `lilygo-firstboot-install.service` executa `setup_swap.sh` antes
de instalar os recursos. O script cria `/swapfile` com 1 GiB, permissões
`0600`, ativa o swap e adiciona uma entrada em `/etc/fstab` para os próximos
boots. Usa espaço da partição raiz, não da partição FAT de boot.
São necessários pelo menos 1088 MiB livres na partição raiz.

Se o swap já existir com o tamanho e formato corretos, ele será reutilizado.
Um arquivo existente com outro tamanho ou conteúdo não será sobrescrito;
a instalação interrompe com uma mensagem no journal, permitindo corrigir
o problema e tentar novamente. Falhas não desabilitam o serviço de instalação.

Verificação após o boot:

```sh
swapon --show
free -h
journalctl -u lilygo-firstboot-install.service
```

Para configurar uma imagem já instalada, copie o script e execute:

```sh
sudo bash setup_swap.sh
```

Teste de integração em Linux (cria temporariamente um arquivo real de 1 GiB,
sem alterar o fstab ou ativar swap no sistema de teste):

```sh
sudo python3 tests/test_setup_swap.py
```

## Validação no aparelho — 12/11/2026

Testado no CM0 via SSH em `192.168.3.246`, kernel
`6.12.34+rpt-rpi-v7`, com 409 MiB de RAM e raiz ext4:

- Arquivo criado: 1.073.741.824 bytes, `root:root`, modo `0600`.
- Criação e ativação concluídas em aproximadamente 2 minutos no microSD.
- `free -h` confirmou `Swap: 1.0Gi`; uso de swap observado antes do reboot.
- Nova execução reutilizou o arquivo e manteve apenas uma entrada no fstab.
- Após reboot, `swapfile.swap` foi ativado automaticamente com sucesso.
- Ethernet continuou funcionando, com 3/3 respostas do gateway.

Registro: `diagnostics/swap-device-validation-20261112.log`.
