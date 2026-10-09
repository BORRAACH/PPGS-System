# Contexto do projeto: PPGS System (pizzeria_system)

> Cole este texto no início da conversa no Claude web. Gerado a partir do grafo de conhecimento (`graphify-out/GRAPH_REPORT.md`, 2291 nós, 4644 arestas, 110 comunidades; construído sobre o commit `0a15771f`) e do README/`architecture/EXPLAIN.md`.

## O que é

Sistema de gestão de pedidos para pizzaria, desktop, com **Python 3.14 + PyQt6 + QML**. Faz:

- lançamento de pedidos por Balcão, Entrega, Salão (mesas), com cardápio de pizzas, lanches, bebidas, açaí e outros;
- geração da comanda em texto com ESC/POS e impressão em impressora térmica (Bematech);
- consulta, edição e exclusão de comandas;
- fechamento de caixa (despesas, extras, contagem), estatísticas (protegidas por senha do dono), cadastro de clientes e usuários, mapa/rotas de entrega;
- **sincronização P2P entre várias máquinas da mesma rede local, sem servidor central.**

Suporta Windows (spooler via `win32print`/PowerShell) e Linux (CUPS `lp`/`lpstat`). macOS não é suportado. Interface e comentários do código estão em **português**.

## Arquitetura em camadas

```
qml/  (UI)  ──context properties──▶  controllers/  (ponte QObject, pyqtSlot/pyqtProperty)
                                           │
                                           ▼
                                      services/  (regras, impressão, endereços, cardápio)
                                           │
                                           ▼
                                   services/rede/  (malha P2P, estado replicado, criptografia)
```

- `main.py` cria a `QGuiApplication`, registra os controllers como context properties e carrega `qml/main.qml`, que tem a barra lateral (`components/LateralBar.qml`) e um `StackView` de páginas.
- `Config/preConfig.py` roda antes de tudo: instala dependências (PyQt6, pywin32, CUPS) se faltarem. `Config/atualizador.py` faz auto-atualização via `git merge` (por isso o `.exe` do Windows, gerado por `launcher/`, é só um lançador e não empacota o código).
- `dev_watch.py` reinicia o app a cada mudança de arquivo.

### Controllers (`controllers/`)
`BalcaoController`, `EntregaController`, `SalaoController`, `ConsultaController`, `FechamentoController`, `EstatisticasController`, `UsuariosController`, `ClientesController`, `RascunhosController`, `RotasController`, `ValidacaoEnderecoController`, `ComandaEstiloController` (o último nasceu do grafo; confirme onde fica).

### Páginas QML (`qml/pages/`)
`inicio`, `balcao`, `entrega`, `salao`, `pedidos` (montagem de item: `pizzas`, `lanches`, `bebidas`, `acai`, `outros`), `consulta`, `fechamento`, `estatistica`, `cardapio`, `mapa`, `rede`, `configuracoes` (impressora, usuários).
Componentes reutilizáveis em `qml/components/` (Botao, Cartao, Dialogo, Tabela, Popup*, helpers `.js` como `MontagemExtras.js`, `RoteiroLancamento.js`). Tema em `qml/estilo/` (`Colors.qml`, `Estilo.qml`, `Responsivo.qml`, `Moeda.qml`, fontes Caprasimo e Figtree). O design system se chama **Paleta Forno** (`design/Paleta Forno.html`).

### Dados
- `data/cardapio/*.json` (`pizzas`, `lanches`, `bebidas`, `outros`, `acai`, `adicionais`, `adicionaisLanches`, `promocoes/`) mais `.sync/versoes.json` para a sincronização do cardápio. O preço dos adicionais de pizza é separado entre **inteira** e **metade** (commit `f70986d`).
- `pedidos/*.txt`: comandas em texto puro; `pedidos/.sync/`: índices, eventos e `clientes.bin` (cadastro cifrado).

## Rede P2P (`services/rede/`), o coração do sistema

- **Descoberta**: mDNS/DNS-SD via `zeroconf` (`descoberta.py`), com broadcast UDP de reserva. Malha completa em TCP, sem servidor.
- **`RedeService`** (105 arestas, segundo maior nó do grafo): anuncia eventos (`anunciar`), inscreve domínios de estado (pedidos, mesas, cardápio, fechamento…), faz gossip e reconciliação por hash diário dentro da janela de retenção, e puxa o que faltou quando um peer volta ou entra.
- **Sincronização de comandas decidida por id de evento** (`indicePedidos.py`, `historicoEventos.py`, `tombstones.py`, `alteracoesComandas.py`, `baixaComandas.py`), com conflitos registrados. Cada comanda tem versão (id de linha do tempo + impressão).
- **Estado replicado por domínio**: `clientes.py`, `usuarios.py`, `despesasCaixa.py`, `extrasCaixa.py`, `edicoesCaixa.py`, `contagemCaixa.py`, `fechamentoCache.py`, `sequenciaComandas.py` (numeração sem colisão entre máquinas, com reserva de faixas), `historicoEnderecos.py`, `indiceRuas.py`, `impressoraFixada.py`, `senhaDono.py`, `relogio.py`.
- **Segurança** (`seguranca.py`, `cofreLocal.py`): só máquinas aprovadas entram. Pareamento por código de 6 dígitos conferido dos dois lados (`SessaoPareamento`, `ErroSeguranca`), chave da malha guardada localmente e cifrada com `cryptography` (DPAPI no Windows, chave própria no Linux). O decorador `protegido()` é o **maior god node do grafo (132 arestas)**: protege ações sensíveis (imprimir, lançar, editar comanda fechada, apagar) exigindo autorização de usuário quando há cadastro.
- **Teste sem hardware**: `docker/docker-compose.yml` sobe 4 instâncias, com scripts `*_teste.py` (sequência, pareamento, cardápio, usuários, estilo, histórico, malha em loop).

## Serviços de domínio (`services/`)

- **Endereços** (grande cluster): `cnefe.py` (base CNEFE/IBGE de ruas), `grafoRuas.py`, `indiceRuas.py`/`montadorIndiceRuas.py`, `validacaoEndereco.py` (CEP, limite de entrega, normalização via `normalizar_endereco`), `sugestoesEndereco.py` (`SugestoesEnderecoService`, mistura histórico local + Photon/geocoding), `enderecoFormatado.py`, `requisicaoHttp.py`.
- **Cardápio**: `cardapioService.py` (com versões para sync), `buscaCardapio.py` (busca por prefixo, promoções do dia).
- **Comanda**: `comandaTextoService.py` (texto ESC/POS), `comandaParserService.py`, `comandaEstiloService.py`, `comandaImagemService.py` (renderização raster), `comandaComparacaoService.py`, `comandaSequencialService.py`. **Ciclo de imports conhecido** entre `comandaEstiloService → comandaImagemService → comandaParserService → comandaEstiloService`.
- **Impressão**: `printerService.py` + `services/printer/` (`linux.py`, `windows.py`, `modelos.py`, `info.py`), com `Config/configurar_impressora_bematech.py` e `diagnosticar_impressora.py`. Se não houver impressora, a comanda é salva mesmo assim.
- **Outros**: `estatisticasService.py`, `rascunhosPedido.py`, `pedidoService.py`, `splashInicializacao.py`/`statusInicializacaoService.py`, `iconProvider.py` (qtawesome), `limpezaServidorAntigo.py` (o antigo `ppgs_server` foi removido).

## Nós mais conectados (pontos de maior impacto ao mexer)

1. `protegido()` (132) · 2. `RedeService` (105) · 3. `FechamentoController` (81) · 4. `SugestoesEnderecoService` (40) · 5. `ConsultaController` (34) · 6. `UsuariosController` (33) · 7. `normalizar()` (33) · 8. `normalizar_endereco()` (27) · 9. `ComandaEstiloController` (26) · 10. `SalaoController` (25).
Mudanças nesses pontos têm raio de impacto grande; leia os chamadores antes de alterar a assinatura.

## Convenções e regras do repositório

- Código, comentários, commits e UI em **português**. Mensagens de commit no imperativo curto, como "Separa o preço dos adicionais de pizza entre inteira e metade".
- **Nunca commitar com `graphify-out/` desatualizado**: antes do primeiro `git commit`, rodar `graphify update .` e incluir `graphify-out/` no último commit da fila (`Atualiza o grafo de conhecimento (graphify-out)`). `graphify-out/` é versionado de propósito.
- Para perguntas de arquitetura, use o grafo antes de varrer arquivos: `graphify query "<pergunta>"`, `graphify path "A" "B"`, `graphify explain "X"`.
- O cardápio em `data/cardapio/` é editado em tempo de execução pela tela Cardápio e sincronizado pela malha; não é código estático.
- A UI QML deve manter o estilo do tema em `qml/estilo/` (Paleta Forno) e usar `Estilo`/`Colors`/`Responsivo` em vez de valores fixos.

## Estado atual do trabalho (em 2026-09-24, branch `master`)

Alterações ainda sem commit: `qml/components/Cartao.qml`, `qml/estilo/Colors.qml`, `qml/estilo/Estilo.qml`, `qml/pages/cardapio/PopupItemCardapio.qml`, `qml/pages/inicio/Inicio.qml`, `qml/pages/pedidos/Pedido.qml`, `data/cardapio/adicionais.json` e `.sync/versoes.json`. Aparenta ser um retoque visual do tema mais o cadastro de adicionais.
Últimos commits: separação do preço dos adicionais (inteira/metade), senha do dono a cada entrada em Estatística, CLAUDE.md com regras do graphify.

## Limitações conhecidas

- Comandas ficam em texto puro em disco; só o cadastro de clientes é cifrado.
- Não há como expulsar uma máquina da malha sem trocar a chave de todas.
- Ambiente Claude web não tem acesso ao código nem ao grafo: cole arquivos específicos quando precisar de revisão detalhada.

## Como me ajudar

Ao responder, considere: PyQt6/QML (Qt 6), Python 3.14, sistema offline-first em rede local, dois SOs, e usuários não técnicos (balcão de pizzaria). Prefira mudanças pequenas e localizadas, sem quebrar a compatibilidade do protocolo da malha entre versões diferentes rodando ao mesmo tempo.
