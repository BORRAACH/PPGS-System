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
- **Rede local entre máquinas** (`services/redeService.py`): ao abrir, cada
  instância do app anuncia e descobre as outras na mesma rede local (UDP
  broadcast) e forma uma malha completa entre elas (TCP), sem nenhuma
  precisar ser "servidor". Pedidos criados/apagados em uma máquina são
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
`preConfig.py` roda primeiro e:
1. Confirma que `PyQt6` (e, no Windows, `pywin32`) importam de verdade; se
   não, instala via `pip install` automaticamente.
2. No Linux, confirma que `lp`/`lpstat` (CUPS) existem; se não, tenta
   instalar pelo gerenciador de pacotes disponível.

Se alguma dessas etapas não conseguir resolver sozinha (sem internet, sem
permissão), o app avisa exatamente o que falhou e o comando pra rodar à
mão, em vez de travar com um traceback.

Depois de rodando, a janela abre direto na tela inicial, com a barra
lateral para navegar entre Balcão, Entrega, Consulta e Rede.

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
controllers/       Ponte QML ↔ Python (Balcão, Entrega, Consulta)
data/cardapio/      Catálogo de pizzas/lanches/bebidas/outros (JSON)
docker/             Ambiente de teste da rede local com múltiplas instâncias
pedidos/            Comandas salvas (.txt), geradas em tempo de execução
qml/                Interface: componentes, páginas e o tema (qml/estilo/)
services/           Impressão (services/printer/) e rede local (redeService.py)
architecture/       Notas de arquitetura (ex: protocolo da rede local)
main.py             Ponto de entrada
preConfig.py         Garante as dependências antes de tudo o mais
```
