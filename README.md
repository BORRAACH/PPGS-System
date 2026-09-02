# PPGS System

Sistema de gestão de pedidos para pizzaria: tirar pedidos no balcão e para
entrega, montar pizzas/lanches/bebidas/outros a partir de um cardápio,
imprimir a comanda na impressora térmica, consultar/editar/apagar comandas
já feitas, e compartilhar os pedidos automaticamente entre várias máquinas
na mesma rede local (sem servidor central).

## Como o projeto funciona

- **Interface**: `PyQt6` + `QML`. `main.py` cria a `QGuiApplication`, sobe
  uma `QQmlApplicationEngine` e carrega `qml/main.qml`, que monta a barra
  lateral de navegação (`qml/components/LateralBar.qml`) e troca de página
  num `StackView` — Balcão, Entrega, Consulta e Rede.
- **Ponte Python ↔ QML**: cada tela fala com um *controller* (`QObject`
  registrado como context property em `main.py`):
  - `BalcaoController` / `EntregaController` (`controllers/`) — recebem os
    dados do pedido montado na tela, geram o texto da comanda (com os
    códigos ESC/POS de negrito da impressora térmica embutidos), salvam em
    `pedidos/*.txt` e mandam imprimir.
  - `ConsultaController` — lista, reabre para edição e apaga as comandas
    salvas em `pedidos/`.
- **Cardápio**: os itens de pizzas/lanches/bebidas/outros vêm de
  `data/cardapio/*.json`, carregados via `XMLHttpRequest` nas telas
  correspondentes (`qml/pages/pedidos/`), usando um caminho absoluto
  montado a partir da raiz do projeto (`raizProjeto`, exposto pelo
  `main.py`) — não depende de onde o `.qml` está na árvore.
- **Impressão** (`services/printerService.py` + `services/printer/`):
  detecta o sistema operacional automaticamente e usa CUPS (`lp`/`lpstat`)
  no Linux ou `win32print`/PowerShell (`Win32_Printer`) no Windows. Se
  nenhuma impressora for encontrada, o pedido continua salvo em
  `pedidos/` mesmo assim — só a impressão falha, sem derrubar o app.
- **Rede local entre máquinas** (`services/rede/`): ao abrir, cada
  instância do app anuncia e descobre as outras na mesma rede local
  (mDNS/DNS-SD, via `zeroconf` — o mesmo mecanismo pelo qual impressoras e
  Chromecasts aparecem sozinhos) e forma uma malha completa entre elas
  (TCP), sem nenhuma precisar ser "servidor". Pedidos criados/apagados em uma máquina são
  transmitidos direto para todas as outras conectadas, e quem estava
  offline recebe o que faltar assim que reconecta. A tela **Rede**
  (`qml/pages/rede/Rede.qml`) mostra quais máquinas estão conectadas agora;
  a tela **Consulta** atualiza sozinha quando um pedido chega pela rede.
  Detalhes do protocolo em [`architecture/EXPLAIN.md`](architecture/EXPLAIN.md).

## Sistemas operacionais suportados

| Sistema | Interface / pedidos / rede local | Impressão |
|---|---|---|
| **Windows** (10+) | ✅ | ✅ (spooler do Windows via `win32print`/PowerShell) |
| **Linux** | ✅ | ✅ (via CUPS — `lp`/`lpstat`) |
| macOS | não testado | ❌ (sem implementação em `services/printer/`) |

Requer **Python 3.14 ou mais recente** (`.python-version` / `pyproject.toml`).

## Dependências

O projeto instala a maior parte sozinho na primeira execução (ver
["Como instalar"](#como-instalar-e-rodar) abaixo) — esta lista é só pra
referência do que é usado por trás:

**Comuns aos dois sistemas**
- Python ≥ 3.14
- [`PyQt6`](https://pypi.org/project/PyQt6/) (interface QML) — instalado
  via pip automaticamente.
- [`qtawesome`](https://pypi.org/project/QtAwesome/) (ícones — Font
  Awesome, Material Design Icons etc., ver `qml/components/Icone.qml`) —
  instalado via pip automaticamente.
- [`zeroconf`](https://pypi.org/project/zeroconf/) (mDNS/DNS-SD: é como
  cada máquina acha as outras na rede local, ver
  `services/rede/descoberta.py`) — instalado via pip automaticamente. Sem
  ele o app ainda abre, e a descoberta cai num broadcast UDP de reserva.

**Windows**
- [`pywin32`](https://pypi.org/project/pywin32/) (acesso ao spooler de
  impressão via `win32print`) — instalado via pip automaticamente.
- PowerShell (`Get-CimInstance`, `Get-PrinterPort`, `Get-PrinterDriver`) e o
  spooler de impressão do Windows — já vêm com o sistema operacional, nada
  a instalar.

**Linux**
- CUPS (comandos `lp` e `lpstat`) para detectar e enviar para impressoras —
  se não estiver instalado, o app tenta instalar sozinho via `apt-get`,
  `dnf`, `yum`, `pacman` ou `zypper` (o que estiver disponível), pedindo
  privilégio de root sem senha; se não conseguir, avisa no console e
  continua funcionando normalmente (só sem imprimir).
- Bibliotecas do Qt6 (OpenGL/EGL, xcb, fontconfig, D-Bus, Kerberos) — numa
  instalação Linux com ambiente gráfico (X11/Wayland) normal, essas já
  costumam estar presentes. Rodando em algo bem mínimo (ex: um container),
  veja a lista completa de pacotes `apt` em
  [`docker/Dockerfile`](docker/Dockerfile).
- Firewall: ao abrir, o sistema tenta abrir portas UDP/TCP locais para a
  rede entre máquinas — se o firewall perguntar, basta permitir.

## Como instalar e rodar

```bash
git clone git@github.com:BORRAACH/PPGS-System.git
cd pizzeria_system
python main.py   # ou "python3 main.py", dependendo do sistema
```

Não precisa instalar nada manualmente antes: ao rodar `main.py`, o
`Config/preConfig.py` roda primeiro e:
1. Confirma que `PyQt6` (e, no Windows, `pywin32`) importam de verdade; se
   não, instala via `pip install` automaticamente.
2. No Linux, confirma que `lp`/`lpstat` (CUPS) existem; se não, tenta
   instalar pelo gerenciador de pacotes disponível.

Se alguma dessas etapas não conseguir resolver sozinha (sem internet, sem
permissão), o app avisa exatamente o que falhou e o comando pra rodar à
mão, em vez de travar com um traceback.

Depois de rodando, a janela abre direto na tela inicial, com a barra
lateral para navegar entre Balcão, Entrega, Consulta e Rede.

### Atalho de duplo clique no Windows (.exe)

Para não precisar abrir o terminal em cada máquina da pizzaria, o diretório
[`launcher/`](launcher/) gera um `SistemaDePedidos.exe`. Rode uma vez, **no
Windows**:

```bat
launcher\gerar_exe.bat
```

O `.exe` aparece na raiz do projeto (alguns MB: o PyInstaller embute o
interpretador Python dentro dele, mesmo o lançador sendo um script curto). Coloque-o na Área de Trabalho como
**atalho** (botão direito no `.exe` > Enviar para > Área de trabalho) — não
copie o arquivo para fora da pasta, porque ele procura o `main.py` ao lado
dele.

Esse executável **não contém o sistema**: ele acha o Python (preferindo o
`.venv` do projeto) e roda o `main.py` que está no disco, sem a janela preta
de console. Isso é de propósito — empacotar o app inteiro num `.exe`
congelaria o código dentro do binário, e a atualização automática
(`Config/atualizador.py`, que faz `git merge` e conta que os imports
seguintes leiam os arquivos novos) deixaria de funcionar; `data/cardapio/`
também precisa continuar no disco, já que a tela Cardápio o edita e a malha
o sincroniza em tempo de execução.

Como consequência, a máquina precisa ter o Python instalado e o projeto
clonado — o mesmo que já é necessário hoje. Se faltar qualquer um dos dois, o
atalho abre uma caixa de erro dizendo exatamente o que fazer, em vez de não
fazer nada ao ser clicado.

Só é preciso gerar o `.exe` de novo se `launcher/iniciar.py` mudar: as
atualizações do sistema continuam chegando por git, sem tocar no executável.

### Servidor central: quem hospeda, e como ele sobe sozinho

Uma única máquina da malha hospeda o `ppgs_server` (o backend em Rust que
guarda os endereços de cliente e o resumo de cada fechamento de caixa). Quem é
ela se escolhe na tela **Rede**, no botão "Rodar nesta máquina" — só essa
máquina baixa e compila o servidor; as outras chegam nele pela malha, já dentro
da sessão autenticada e cifrada, sem IP nem porta para configurar.

Nessa máquina, marque também **"Iniciar com o Windows"** no mesmo cartão. Isso
cria um atalho na pasta Inicializar do Windows, e a partir daí uma queda de
energia ou um reinício noturno não deixam a pizzaria sem servidor: o Windows
abre o sistema, e o sistema sobe o servidor. É preciso ser o sistema quem sobe,
e não o servidor sozinho: as outras máquinas falam com ele *pela malha*, que só
existe com o app aberto.

O servidor **não cai quando o sistema é fechado**. Ele sobe destacado do app e,
na abertura seguinte, é adotado como está em vez de reiniciado — o que acaba
com a janela de alguns segundos (ou minutos, quando havia compilação) sem
servidor a cada fechar/abrir. Quem o derruba de propósito é o botão "Parar" da
tela Rede.

**Nada se perde quando o servidor está fora do ar.** Endereços de cliente e
fechamentos de caixa vão primeiro para uma fila em disco
(`pedidos/.sync/envios_servidor.json`) e só saem dela quando o servidor
confirma a gravação — então o balcão continua perguntando "salvar o endereço
deste cliente?" com a máquina hospedeira desligada, e o cadastro sobe sozinho
quando ela voltar, inclusive depois de o sistema ter sido fechado no meio.

O banco é copiado uma vez por dia para
`%LOCALAPPDATA%\PPGS\dados\backups\pizzeria-AAAA-MM-DD.db`, guardando as
últimas 14 cópias.

### Rodando em mais de uma máquina

Basta abrir o app normalmente em cada computador da mesma rede local — elas
se encontram sozinhas. Não é necessário configurar IP, servidor ou nada
manual; acompanhe pela tela **Rede** quantas máquinas estão conectadas.

### Testando a malha de rede sem várias máquinas físicas

O diretório [`docker/`](docker/) sobe 4 instâncias do app em containers
separados (rede isolada) para validar a descoberta e sincronização entre
"máquinas" sem precisar de hardware extra — ver os comentários no topo de
`docker/docker-compose.yml` para o passo a passo.

### Durante o desenvolvimento

`dev_watch.py` roda `main.py` num subprocesso e reinicia sozinho a cada
mudança de arquivo do projeto — útil para não precisar reiniciar
manualmente a cada edição:

```bash
python dev_watch.py
```

## Estrutura do projeto

```
Config/            Dependências (preConfig.py) e setup de impressora (Linux)
controllers/       Ponte QML ↔ Python (Balcão, Entrega, Consulta)
data/cardapio/     Catálogo de pizzas/lanches/bebidas/outros (JSON)
docker/            Ambiente de teste da rede local com múltiplas instâncias
pedidos/           Comandas salvas (.txt), geradas em tempo de execução
qml/               Interface: componentes, páginas e o tema (qml/estilo/)
services/          Impressão (services/printer/) e rede local (services/rede/)
architecture/      Notas de arquitetura (ex: protocolo da rede local)
main.py            Ponto de entrada
```
