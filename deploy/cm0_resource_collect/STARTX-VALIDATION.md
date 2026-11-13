# Teste real do startx — CM0, 12/11/2026

O `startx` foi iniciado às 13:10 como usuário `kali`, no console virtual
local tty1, usando uma unidade temporária systemd com sessão PAM login.
Comando: `startx -- vt1 -keeptty`. O LightDM não foi habilitado.

## Resultado

- Xorg 21.1.24 e Xfce permaneceram ativos durante a verificação.
- Processos presentes: Xorg, xfce4-session, xfwm4, xfce4-panel e xfdesktop.
- DSI-1 conectado e habilitado, 568 × 1232 pixels, 35 Hz.
- `xset q`: `Monitor is On`.
- Estado DRM: framebuffer alocado pelo Xorg, 568 × 1232, formato XR24,
  associado ao controlador `pixelvalve-1`.
- Captura de tela mostra painel superior do Xfce e ícones Home, File System
  e Trash sobre fundo preto. Não é uma captura uniformemente preta.
- `glxinfo -B`: renderização direta e acelerada, Broadcom VC4 V3D 2.1,
  OpenGL 2.1 / OpenGL ES 2.0, Mesa 26.1.6-1; terminou com código zero.
  Uma primeira tentativa com limite de 15 segundos não concluiu; a repetição
  posterior com limite de 20 segundos completou.
- Nenhuma linha real `(EE)` no log atual do Xorg, nem erro DRM/DSI ou OOM
  no trecho do kernel correspondente ao teste.

Isso sustenta a inferência de que a sessão está renderizando e enviando
imagem ao painel. Software não comprova a emissão física de luz ou a
integridade visual do painel sem observação externa.

## Avisos atuais

| Mensagem | Interpretação |
| --- | --- |
| Diretório `/usr/share/fonts/X11/cyrillic` ausente | Diretório de fontes opcionais; outras fontes carregadas e texto presente na captura. |
| `Falling back to old probe method for fbdev` | Aviso na descoberta de drivers; o driver realmente usado foi modesetting/VC4. |
| `VGA arbiter: cannot open kernel arbiter` | Ausência do árbitro VGA; não impediu o uso do controlador ARM/DSI. |
| `Failed to fetch _NET_*` | Mensagens durante a inicialização; depois o gerenciador de janelas e a área de trabalho responderam. |
| `SSH authentication agent is already running` / gpg-agent já ativo | Agentes existentes reutilizados; a sessão continuou. |
| polkit-mate: `g_variant_new_string` e `org.gnome.SessionManager` não disponível | Avisos do agente de autenticação/integração de sessão. O processo permaneceu ativo, mas não foi testado um diálogo de autorização. |
| blueman: `Adapter is None` e conflitos de plugins | Bluetooth indisponível; o boot já contém `dtoverlay=disable-bt`. Não impede o desktop. |

O `/var/log/Xorg.0.log` e o início de `.xsession-errors` continham registros
de uma sessão anterior; os resultados acima usam o log atual em
`/home/kali/.local/share/xorg/Xorg.0.log` e o trecho da sessão de hoje.

## Memória e estado deixado

Na amostra das 13:13: RAM total de 409 MiB, 201 MiB usados, 208 MiB
disponíveis; swap em uso de aproximadamente 180 MiB. Houve lentidão durante
o carregamento inicial, mas os componentes da sessão continuaram ativos.

A interface foi mantida aberta em uma unidade temporária:

```sh
sudo systemctl status cm0-startx-test.service
sudo systemctl stop cm0-startx-test.service
```

Ao encerrar a unidade, uma ação temporária restaura o getty da tty1.
A unidade e sua configuração em `/run/systemd/system` desaparecem no reboot.

Logs e captura: `diagnostics/startx-20261112/`.

## Novo teste às 20:33 — relato físico de tela preta

Após o usuário informar a recuperação do I²C e do display, o Xfce foi iniciado
novamente. Xorg, sessão, gerenciador de janelas e painel iniciaram, com DSI
568 × 1232 a 35 Hz. RTC e bateria responderam às leituras durante o teste.
Os logs deste teste ficam em `diagnostics/startx-20261112-2033/`.

O usuário informou que o display ficou preto e confirmou que continuou preto
ao alternar para um console com texto de diagnóstico. Portanto o teste não
confirmou funcionamento físico da imagem, apesar de o software renderizar.
Foi forçada nova inicialização DSI às 20:38, com disable/unprepare e
prepare/enable registrados. A resposta visual após esse ciclo ficou pendente.
Leituras MIPI DCS adicionais estão documentadas em
`diagnostics/panel-status-20261112/README.md`.

## Padrão interno confirmado com driver atualizado

O primeiro BIST local continuou preto segundo o usuário. Depois foi usado
o fonte atualizado do fabricante, com a sequência que ativa o painel antes
de programar o padrão interno. O usuário então confirmou imagem/cores.
Os detalhes e binários estão em `diagnostics/panel-upstream-v2-20261112/`.

O autoteste foi posteriormente desativado e foi carregada a variante normal
do mesmo driver (srcversion `32B24DA6A208278B84833B6`). Xorg e Xfce iniciaram
em 568×1232/35 Hz/RGB888. A confirmação física dessa sessão normal ainda
estava pendente. Logs: `diagnostics/xfce-upstream-normal-20261112/`.

## Console recuperado após os testes (21:41)

Depois de restaurar o driver normal 32B24DA6A208278B84833B6 e reiniciar,
o usuário relatou texto do boot até o login, seguido de tela preta.
Não havia Xorg ativo e consoleblank estava em 0. Executar chvt 1,
setterm --blank 0 --powerdown 0, setterm --blank poke e escrever novamente
no tty1 recuperou a imagem, confirmada visualmente pelo usuário.
Essas ações não reinicializaram o painel nem carregaram outro driver.
Isso impede concluir que a falha seja exclusiva do Xorg ou aceleração.

Nos ensaios anteriores, xmessage com modesetting e com fbdev de 16 bits
ficou preto; a variante sem backlight dinâmico também não resolveu.
Ela foi retirada, mantendo o driver normal restaurado. O problema gráfico
continua sem correção validada. Evidências: diagnostics/minimal-x-20261112/
e diagnostics/panel-static-brightness-20261112/.