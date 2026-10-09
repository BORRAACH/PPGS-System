# Graph Report - pizzeria_system  (2026-10-09)

## Corpus Check
- 119 files · ~172,248 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 99 file(s) not represented in the graph (top: .qml 87, (none) 6, .ttf 5)

## Summary
- 2349 nodes · 4787 edges · 119 communities (108 shown, 11 thin omitted)
- Extraction: 99% EXTRACTED · 1% INFERRED · 0% AMBIGUOUS · INFERRED: 67 edges (avg confidence: 0.9)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `149ab716`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- SugestoesEnderecoService
- ErroSeguranca
- cardapioService.py
- atualizador.py
- ConsultaController
- UsuariosController
- indicePedidos.py
- cnefe.py
- SalaoController
- senhaDono.py
- validar
- RedeService
- buscaCardapio.py
- comandaParserService.py
- indiceRuas.py
- historicoEnderecos.py
- Descoberta
- sugestoesEndereco.py
- FechamentoController
- ValidacaoEnderecoController
- protegido
- comandaEstiloService.py
- comandaImagemService.py
- sys
- requisicaoHttp.py
- pyqtSlot
- EstatisticasController
- ._processar_mensagem
- configurar_impressora_bematech.py
- QTcpSocket
- linux.py
- historicoEventos.py
- grafoRuas.py
- _desenhar_modelo_classico
- usuarios.py
- _EscritaParaLog
- pyqtSlot
- seguranca.py
- preConfig.py
- pyqtProperty
- os
- RotasController
- info.py
- estatisticasService.py
- ._calcular_resumo_dia
- rascunhosPedido.py
- tombstones.py
- cofreLocal.py
- alteracoesComandas.py
- sequenciaComandas.py
- diagnosticar_impressora.py
- _bloco_tabela_rascunho
- comandaTextoService.py
- edicoesCaixa.py
- taxasBairro.py
- EntregaController
- despesasCaixa.py
- novo_id
- PrinterService
- _aplicar_estilo_remoto
- baixaComandas.py
- .criarRede
- splashInicializacao.py
- clientes.py
- Controllers (`controllers/`)
- windows.py
- caminhos.py
- ClientesController
- dev_watch.py
- validacaoEndereco.py
- montadorIndiceRuas.py
- redeQml.py
- re
- .registrarEdicaoCaixa
- SessaoSegura
- ._recalcular_e_cachear
- graphify
- pareamento_teste.py
- .listarRascunhos
- subprocess
- MontagemExtras.js
- _desenhar_modelo_rascunho
- normalizar
- BarramentoEventos
- iconProvider.py
- DestinoPedido.js
- _linhas_com_estilo
- ._recalcular_maquina_impressora
- instalar_captura_de_mensagens_qt
- ._montar_recibo_extra
- endereco_da_comanda
- fechamentoCache.py
- aquecer_familias
- ._tentar_conectar_a_peer
- ResumoExtras.js
- Texto.js
- BuscaComandas.js
- MontagemItem.js
- Formato.js
- impressoraWindows.py
- TaxasBairroController
- ._aplicar_localizacao
- StatusInicializacaoService
- faixa_de_numeros
- .listarComandasAbertas
- limpezaServidorAntigo.py
- ._registrar_baixa_aprendida
- RoteiroLancamento.js
- redeService.py
- ._registrar_edicao_aprendida
- Paleta Forno Design System
- ._aplicar_exclusao_extra
- reservar
- .__init__
- _iniciar_rede
- Docker Compose Mesh Test
- pizzeria-system

## God Nodes (most connected - your core abstractions)
1. `protegido()` - 137 edges
2. `RedeService` - 107 edges
3. `FechamentoController` - 83 edges
4. `SugestoesEnderecoService` - 42 edges
5. `ConsultaController` - 36 edges
6. `UsuariosController` - 35 edges
7. `normalizar()` - 33 edges
8. `normalizar_endereco()` - 31 edges
9. `ComandaEstiloController` - 28 edges
10. `SalaoController` - 27 edges

## Surprising Connections (you probably didn't know these)
- `Rede P2P (`services/rede/`), o coração do sistema` --references--> `protegido()`  [INFERRED]
  CONTEXTO_CLAUDE_WEB.md → Config/logConfig.py
- `Controllers (`controllers/`)` --references--> `BalcaoController`  [INFERRED]
  CONTEXTO_CLAUDE_WEB.md → controllers/balcaoController.py
- `Como o projeto funciona` --references--> `BalcaoController`  [INFERRED]
  README.md → controllers/balcaoController.py
- `Controllers (`controllers/`)` --references--> `ClientesController`  [INFERRED]
  CONTEXTO_CLAUDE_WEB.md → controllers/clientesController.py
- `Controllers (`controllers/`)` --references--> `ConsultaController`  [INFERRED]
  CONTEXTO_CLAUDE_WEB.md → controllers/consultaController.py

## Import Cycles
- 3-file cycle: `services/comandaEstiloService.py -> services/comandaImagemService.py -> services/comandaParserService.py -> services/comandaEstiloService.py`

## Hyperedges (group relationships)
- **Design System Foundations** — design_paleta_forno, qml_estilo_fontes_caprasimo, qml_estilo_fontes_figtree, design_food_color_palette [INFERRED 0.85]

## Communities (119 total, 11 thin omitted)

### Community 0 - "SugestoesEnderecoService"
Cohesion: 0.05
Nodes (29): _bairros_do_photon(), _features_de(), pyqtProperty, pyqtSlot, QObject, [(properties, coordinates)] do GeoJSON do Photon, ou None se a resposta não…, Ruas salvas nesta máquina (histórico e índice) que casam com `termo` —…, Mesmo papel de sugerirEnderecosLocais, para o campo Bairro. (+21 more)

### Community 1 - "ErroSeguranca"
Cohesion: 0.19
Nodes (8): ErroSeguranca, Exception, Falha de handshake ou de abertura de frame. Quem trata fecha o socket — nunca…, Entrega a chave da malha a uma máquina nova, com uma pessoa conferindo um…, Os dois lados já chegaram ao código (depois da revelação)., Consome a resposta e devolve o frame de revelação a mandar., Consome o pedido e devolve o frame de resposta a mandar., SessaoPareamento

### Community 2 - "cardapioService.py"
Cohesion: 0.06
Nodes (42): Verifica manualmente a sincronização do cardápio entre "máquinas", em especial…, resumo(), tick(), _caminho_arquivo(), _caminho_versoes(), CardapioController, carregar(), _carregar_versoes() (+34 more)

### Community 3 - "atualizador.py"
Cohesion: 0.06
Nodes (52): _arquivos_cardapio_modificados_localmente(), _atualizar(), _branch_atual(), _caminho_relativo_cardapio(), checar_atualizacoes(), _commits_atras(), _desfazer_guarda_cardapio_local(), _eh_repositorio_git() (+44 more)

### Community 4 - "ConsultaController"
Cohesion: 0.06
Nodes (27): ConsultaController, pyqtSlot, QObject, Descarta os conflitos que a regra antiga gravou sem olhar conteúdo. Até aqui…, A "versão" de cada comanda é o id de linha do tempo dela MAIS a impressão…, Decide se vale puxar do peer a comanda `nome_arquivo`. Só o transporte decide…, A data mais antiga (como "AAAAMMDD") que ainda conta como recente. Mesma…, 20260731" -> "31/07/2026", o mesmo formato do cabeçalho do cupom (e o que… (+19 more)

### Community 5 - "UsuariosController"
Cohesion: 0.06
Nodes (24): pyqtSlot, QObject, Sem janela temporal, ao contrário de "extras"/"fechamento": um cadastro não é…, Reação ao gossip "usuario_alterado" — para um cadastro novo OU uma correção…, Grava um usuário aprendido de fora, venha ele do gossip ou da reconciliação —…, Todos os usuários, ordenados por nome, cada um com "duplicado": True quando…, Tudo que se sabe sobre uma pessoa do cadastro, para o popup que abre ao clicar…, Se as ações protegidas (imprimir, lançar, editar comanda fechada, apagar… (+16 more)

### Community 6 - "indicePedidos.py"
Cohesion: 0.08
Nodes (43): contextlib, _calcular_impressao(), _caminho_conflitos(), _caminho_eventos(), _carregar(), carregar_conflitos(), carregar_indice(), _carregar_para_gravar() (+35 more)

### Community 7 - "cnefe.py"
Cohesion: 0.08
Nodes (44): csv, io, bairros_da_rua(), baixar_e_montar(), buscar_ruas(), caminho_banco(), _carregado(), casa() (+36 more)

### Community 8 - "SalaoController"
Cohesion: 0.09
Nodes (23): _chave_item(), _item_sem_precos(), _itens_pendentes_cozinha(), _itens_reais(), pyqtSlot, QObject, Gerencia comandas de mesa (Salao.qml): diferente de Balcão/Entrega, uma comanda…, Todas as mesas abertas gravadas localmente, como dicts completos (não só o… (+15 more)

### Community 9 - "senhaDono.py"
Cohesion: 0.14
Nodes (22): aplicar_remoto(), _bytes_da_senha(), _caminho_arquivo(), carregar(), conferir(), definida(), definir(), _derivar() (+14 more)

### Community 10 - "validar"
Cohesion: 0.12
Nodes (23): cep_da_rua(), do_bairro(), cep_digitos(), _cep_util(), formatar_cep(), limite_entrega(), mesma_rua(), _numero_na_faixa() (+15 more)

### Community 11 - "RedeService"
Cohesion: 0.06
Nodes (15): QObject, Aprende reservas de número feitas em outra máquina. É este caminho — não a…, Quando um peer NOVO entra na malha (a quantidade aumentou, não só mudou),…, Anuncia `payload` (precisa ser serializável em JSON) pra malha inteira sob o…, Registra `callback(payload)` pra rodar sempre que um evento `tipo_evento`…, Anuncia um hash por dia, só dos dias dentro da janela de retenção. A janela…, As fontes da máquina que a malha está usando pra imprimir agora, pra alimentar…, Roda em thread própria (ver solicitar_impressao) — a impressão (spooler/CUPS)… (+7 more)

### Community 12 - "buscaCardapio.py"
Cohesion: 0.08
Nodes (38): bisect, analisar_item_comanda(), _aplicar_promocao(), aquecer(), _arquivo_promocao_do_dia(), _assinatura_dos_arquivos(), buscar(), _carregar_promocoes() (+30 more)

### Community 13 - "comandaParserService.py"
Cohesion: 0.08
Nodes (33): campos_comparaveis(), comparar(), diferencas_entre(), _formatar(), Compara duas versões da MESMA comanda campo a campo, para dizer se elas são de…, Lista vira uma linha por elemento; o resto vira texto puro. É o que a tela…, Os campos cujo valor difere entre as duas versões, na ordem de ROTULOS (a mesma…, Atalho para os dois passos acima, que é como quem chama sempre usa. (+25 more)

### Community 14 - "indiceRuas.py"
Cohesion: 0.09
Nodes (44): aplicar_montagem(), aplicar_remoto(), base(), bloco_da_chave(), buscar_ruas(), _caminho_arquivo(), _carregar(), chave_rua() (+36 more)

### Community 15 - "historicoEnderecos.py"
Cohesion: 0.13
Nodes (31): aplicar_remoto(), aprendido(), buscar_bairros(), buscar_ruas(), _caminho_arquivo(), carregar(), _casa(), chave() (+23 more)

### Community 16 - "Descoberta"
Cohesion: 0.09
Nodes (10): Descoberta, DescobertaBroadcast, DescobertaZeroconf, QObject, Interface comum das estratégias de descoberta. Emite `peerDescoberto` para cada…, Começa a anunciar esta instância e a procurar as outras. `porta_tcp` é a porta…, A máquina entrou numa rede: o anúncio passa a dizer isso, para as pareadas…, Descoberta por mDNS/DNS-SD: anuncia esta instância como um serviço `_pizzaria-… (+2 more)

### Community 17 - "sugestoesEndereco.py"
Cohesion: 0.10
Nodes (30): concurrent_futures, Validação do endereço de entrega (qml/components/DeliveryAddressValidator.qml).…, A sugestão da casa `numero` da `rua`: a da última comanda para ela, senão a do…, As sugestões desta máquina para a rua digitada (ver o topo), com a grafia do…, bairros_equivalentes(), escolher_bairro(), formatar_endereco(), normalizar_endereco() (+22 more)

### Community 18 - "FechamentoController"
Cohesion: 0.07
Nodes (9): FechamentoController, QObject, Fechamento de caixa diário: soma o valor das comandas **fechadas**…, Payload deliberadamente vazio de números: quem recebe recalcula o dia com as…, Anuncia as baixas recentes. A janela recorta só o que é ANUNCIADO: o arquivo em…, Só puxa o que não existe aqui. O comparador padrão de…, Anuncia os pagamentos de diária recentes, na mesma janela do domínio…, Anuncia as alterações recentes, na mesma janela dos outros domínios do caixa:… (+1 more)

### Community 19 - "ValidacaoEnderecoController"
Cohesion: 0.12
Nodes (13): pyqtSlot, QObject, {rua, numero, bairro, pistaCondominio} do texto livre: o Enter sem escolher…, Síncrono, a cada tecla: histórico e índice de ruas desta máquina., Locais + Photon, numa thread. Responde por sugestoesProntas., Valida a sugestão escolhida com o número do campo. Responde por validacaoPronta…, Mesma validação, partindo do CEP digitado pelo atendente., Carrega o grafo de ruas em segundo plano (cache ou download), uma vez só. (+5 more)

### Community 20 - "protegido"
Cohesion: 0.09
Nodes (23): protegido(), decorar(), Decorador para os métodos expostos à QML (os @pyqtSlot dos controllers):…, Nós mais conectados (pontos de maior impacto ao mexer), ComandaEstiloController, _modalidade_do_exemplo(), ordem_secoes(), _padrao() (+15 more)

### Community 21 - "comandaEstiloService.py"
Cohesion: 0.08
Nodes (34): hashlib, atributos_campo(), _atributos_campo_padrao(), _caminho_arquivo(), _carregar(), _comando_tamanho_fonte(), _comando_tamanho_px(), fonte_impressao() (+26 more)

### Community 22 - "comandaImagemService.py"
Cohesion: 0.10
Nodes (35): _altura_da_linha(), _comandos_raster(), _desenhar_icone(), desenhar_qr_endereco(), _desenhar_titulo(), _despejar_palavra(), _empacotar(), _estilo_de_campo() (+27 more)

### Community 23 - "sys"
Cohesion: 0.10
Nodes (12): Registra as fontes embarcadas do app e define a Figtree como fonte padrão. Por…, Simula apagar a comanda mais recente desta "máquina" (container), usando o…, Verifica manualmente a sincronização de Config/estilo_impressao.json entre…, Simula alguém tirando um pedido no Balcão desta "máquina" (container), usando o…, Verifica manualmente o histórico de eventos da malha…, tick(), Mostra quais outras "máquinas" (containers) esta instância enxerga na malha…, Fica rodando e imprimindo a letra desta "máquina" a cada 3s — usado só… (+4 more)

### Community 24 - "requisicaoHttp.py"
Cohesion: 0.11
Nodes (19): certifi, gzip, baixar_arquivo(), _corpo(), ErroRequisicao, obter_json(), obter_texto(), Exception (+11 more)

### Community 25 - "pyqtSlot"
Cohesion: 0.09
Nodes (14): _hoje_iso(), pyqtSlot, Se o resumo em cache foi gravado por uma versão do app que já montava tudo que…, Manda a comanda pra impressora exatamente como ela está em disco, `copias`…, Fecha a comanda: a partir daqui ela conta no caixa do dia. Não há operação…, Lança um pagamento de diária no dia `data_iso` e devolve o registro gravado…, Corrige o nome/valor de um pagamento de diária já lançado — mesmo id, mesma…, Apaga um pagamento de diária já lançado (ver… (+6 more)

### Community 26 - "EstatisticasController"
Cohesion: 0.12
Nodes (13): EstatisticasController, trabalho(), _hoje_iso(), pyqtSlot, QObject, As alterações do dia. As correções de caixa gravadas antes de…, Monta e grava `data_iso`. Devolve as estatísticas gravadas., Chamado pelo "Fechar Caixa": grava o dia e avisa as outras máquinas. (+5 more)

### Community 27 - "._processar_mensagem"
Cohesion: 0.12
Nodes (5): Ponte entre BarramentoEventos e os sockets reais: manda `evento` pra todo peer…, Um ciclo de anti-entropy: monta o resumo atual de cada domínio registrado e…, Compara o resumo recebido de um peer com o estado local de cada domínio: aplica…, Chamado ao processar o handshake "identificar" de um peer que acabou de…, Pede a impressão da comanda na máquina eleita da malha (ver…

### Community 28 - "configurar_impressora_bematech.py"
Cohesion: 0.27
Nodes (17): aplicar_modo_raw_imediatamente(), configurar_fila_cups(), encontrar_dispositivo_tty(), encontrar_stty(), enviar_teste(), executar(), exigir_root(), garantir_cups_instalado() (+9 more)

### Community 29 - "QTcpSocket"
Cohesion: 0.16
Nodes (9): QTcpSocket, Um socket de pareamento fechou (ou foi fechado). Do lado que aprova, o pedido…, Devolve False quando o socket foi recusado e não se deve continuar lendo os…, Lado que PEDE: abre o pareamento com a máquina escolhida, por todos os…, Fecha e registra. O registro é o ponto: uma máquina recusada (hoje, na prática,…, Um socket que nunca chegou a conectar não emite `disconnected`, então…, Primeiro frame de uma conexão de entrada. Devolve False quando o socket foi…, Lado que APROVA: uma máquina sem chave pediu para entrar. (+1 more)

### Community 30 - "linux.py"
Cohesion: 0.14
Nodes (24): _classificar_porta(), coletar_impressoras(), _descricao_e_status(), _destino_padrao(), _dispositivos_conectados_agora(), _dispositivos_por_impressora(), _executar(), _extrair_porta() (+16 more)

### Community 31 - "historicoEventos.py"
Cohesion: 0.12
Nodes (25): aplicar(), _caminho(), _carregar(), contar_autorizacoes(), _detalhe_de(), listar(), obter(), _purgados() (+17 more)

### Community 32 - "grafoRuas.py"
Cohesion: 0.06
Nodes (35): heapq, math, baixar_elementos(), _caminho_cache(), comparar_entregas(), _consulta_overpass(), _distancia_m(), ErroRota (+27 more)

### Community 33 - "_desenhar_modelo_classico"
Cohesion: 0.15
Nodes (16): _desenhar_modelo_classico(), _espessura_do_traco(), _icones_da_comanda(), _linhas_entre_itens(), A linha como ela sai no papel: os trechos concatenados, já sem os comandos de…, A espessura do traço que substitui esta linha, ou None se ela é texto. As duas…, {índice: espessura} das linhas que o próprio texto do cupom já diz serem traço…, Índices das linhas lógicas que separam um item do outro dentro da tabela de… (+8 more)

### Community 34 - "usuarios.py"
Cohesion: 0.15
Nodes (23): apagar(), aplicar_edicao_remota(), _caminho_arquivo(), carregar(), codigo_em_uso(), editar(), existe_algum(), listar() (+15 more)

### Community 35 - "_EscritaParaLog"
Cohesion: 0.15
Nodes (10): caminho_arquivo_log(), configurar_logging(), _EscritaParaLog, _instalar_captura_de_excecoes(), _ao_escapar_excecao(), _ao_escapar_excecao_em_thread(), _raiz_projeto(), Faz toda exceção não tratada virar linha no log — e, no caso das que vêm de… (+2 more)

### Community 36 - "pyqtSlot"
Cohesion: 0.14
Nodes (7): pyqtSlot, Máquinas que anunciam impressora agora (esta + peers) — as opções disponíveis…, Info da impressora que a malha está usando pra imprimir agora (a máquina eleita…, Lado que APROVA: entrega a chave da rede à máquina que pediu. Quem chama já…, Máquinas atualmente conectadas na malha, mais recente primeiro., Histórico da malha para a tela de Rede, mais recente primeiro (ver…, Categorias existentes, para montar o filtro da tela sem repetir a lista no QML.

### Community 37 - "seguranca.py"
Cohesion: 0.10
Nodes (21): cryptography_hazmat_primitives, cryptography_hazmat_primitives_asymmetric_x25519, cryptography_hazmat_primitives_ciphers_aead, cryptography_hazmat_primitives_kdf_hkdf, hmac, secrets, _caminho_chave(), carregar_chave() (+13 more)

### Community 38 - "preConfig.py"
Cohesion: 0.14
Nodes (21): _comandos_de_instalacao(), _configurar_estilo_qt_quick(), _dependencias_aplicaveis(), _dica_pacote_da_distro(), _em_ambiente_virtual(), _erro_de_import(), garantir_dependencias(), _garantir_modulo() (+13 more)

### Community 39 - "pyqtProperty"
Cohesion: 0.10
Nodes (9): pyqtProperty, Nome da máquina fixada manualmente (ver fixarImpressoraPrincipal), ou "" quando…, {"endereco", "descricao", "cidade", "lat", "lon", "origem", "idEvento"}, ou {}…, Máquinas pareadas que esta enxerga enquanto não tem chave., O pedido de entrada feito por esta máquina: {} ou {"id", "nome", "estado",…, Pedidos de outras máquinas esperando aprovação aqui., Quem guarda a chave local desta máquina (ver cofreLocal.protecao): a tela avisa…, Letra (A, B, C...) desta máquina por ordem de entrada dos PROCESSOS atualmente… (+1 more)

### Community 40 - "os"
Cohesion: 0.11
Nodes (28): Redireciona toda a saída do app (stdout/stderr) — incluindo os inúmeros…, Cadastro de clientes da Entrega: busca por telefone (o autofill) e gravação,…, Estatísticas diárias (services/estatisticasService.py) para o "Fechar Caixa" e…, QObject, RascunhosController, Os pedidos começados e não finalizados, para a faixa no topo de Balcão e…, Comparação de rotas de entrega da tela Mapa (qml/pages/mapa/Maps.qml): com a…, Taxa de entrega por bairro: a Entrega consulta ao preencher o bairro e grava… (+20 more)

### Community 41 - "RotasController"
Cohesion: 0.16
Nodes (7): pyqtProperty, pyqtSlot, QObject, Responde por comparacaoPronta (o dict de grafoRuas.comparar_entregas) ou…, Fechamento do sistema: um download em andamento não tenta o próximo servidor., Garante o grafo em memória, do cache ou baixado. Não faz nada se ele já está…, RotasController

### Community 42 - "info.py"
Cohesion: 0.20
Nodes (13): copy, coletar_informacoes_impressoras(), _coletar_sem_cache(), enviar_para_impressora(), invalidar_cache(), Descarta o resultado guardado — a próxima coleta varre de novo. Para quem…, As impressoras instaladas, reaproveitando a última varredura se ela tem menos…, Coleta as impressoras instaladas no sistema operacional atual. Detecta… (+5 more)

### Community 43 - "estatisticasService.py"
Cohesion: 0.16
Nodes (19): agregar(), _caminho(), carregar(), _centavos(), data_valida(), datas_do_periodo(), _hora(), listar_dias() (+11 more)

### Community 44 - "._calcular_resumo_dia"
Cohesion: 0.12
Nodes (9): fmt(), {"dinheiro", "pix", "cartao"} com a soma de `comandas` (a lista já filtrada de…, Bloco "ALTERAÇÕES APÓS A BAIXA" do cupom: uma entrada por comanda já fechada…, Monta, em bytes ESC/POS, o cupom-resumo impresso ao clicar "Fechar Caixa":…, Imprime o cupom-resumo do dia (ver _montar_recibo_fechamento). Chamado só pelo…, Uma comanda qualquer do disco, no mesmo formato de listarComandasAbertas mais o…, Abre uma comanda do dia e extrai dela os campos de cabeçalho que tanto o resumo…, Os itens do pedido de volta a partir do cupom já lido (desfaz… (+1 more)

### Community 45 - "rascunhosPedido.py"
Cohesion: 0.19
Nodes (18): apagar(), _caminho(), _ler(), listar(), _normalizar_id(), obter(), pasta(), purgar_antigos() (+10 more)

### Community 46 - "tombstones.py"
Cohesion: 0.17
Nodes (20): mais_novo(), True se `id_a` é estritamente mais recente que `id_b`. Único ponto de…, _caminho_arquivo(), carregar(), _carregar_tudo(), mesclar(), _migrar_formato_antigo(), _migrar_valor_antigo() (+12 more)

### Community 47 - "cofreLocal.py"
Cohesion: 0.19
Nodes (21): _caminho_arquivo(), _caminho_marca(), _caminho_windows(), _chave_linux(), _chave_windows(), cifrar(), decifrar(), _decodificar() (+13 more)

### Community 48 - "alteracoesComandas.py"
Cohesion: 0.21
Nodes (15): aplicar(), _caminho_arquivo(), carregar(), dias_com_alteracoes(), listar_do_dia(), obter(), Registro persistido de TODA edição e exclusão de comanda — com baixa ou sem —…, Grava uma alteração aprendida de outra máquina. Devolve o dia atingido quando… (+7 more)

### Community 49 - "sequenciaComandas.py"
Cohesion: 0.18
Nodes (17): _caminho_arquivo(), carregar(), dia(), dias_recentes(), _maior_numero(), mesclar_dia(), purgar_antigos(), Registro das reservas de número de comanda do dia — o que faz os dois últimos… (+9 more)

### Community 50 - "diagnosticar_impressora.py"
Cohesion: 0.15
Nodes (18): argparse, config, _executavel_powershell(), listar_impressoras(), log(), main(), _payload_teste(), _payload_teste_raster() (+10 more)

### Community 51 - "_bloco_tabela_rascunho"
Cohesion: 0.12
Nodes (13): _bloco_tabela_rascunho(), _Celula, _colunas_rascunho(), _largura_da_coluna_valor(), Um pedaço de texto a desenhar num retângulo: o texto, a fonte dele e onde ele…, A altura que este texto ocupa na coluna, decidindo de passagem como ele vai…, (x, largura) de cada uma das três colunas, em dots, dada a largura já medida da…, + BACON (R$ 5,00)", e com o sabor no fim quando a pizza tem mais de um — senão,… (+5 more)

### Community 52 - "comandaTextoService.py"
Cohesion: 0.06
Nodes (46): _linhas_itens_producao(), Tabela de itens da comanda do pizzaiolo — mesma montagem de grupos de…, categoria_campo(), formatar_campo(), linhas_espacamento_secoes(), linhas_separador_antes(), _montar_linha_exemplo(), Uma linha da comanda de exemplo, a partir dos trechos que a tela mandou (ver… (+38 more)

### Community 53 - "edicoesCaixa.py"
Cohesion: 0.19
Nodes (16): aplicar(), _caminho_arquivo(), carregar(), contar_do_usuario(), listar_do_dia(), obter(), Registro persistido das ALTERAÇÕES feitas em comandas que já receberam baixa —…, Grava uma alteração e devolve o id do registro. `quando` vem preenchido quando… (+8 more)

### Community 54 - "taxasBairro.py"
Cohesion: 0.25
Nodes (16): aplicar_remoto(), _caminho_arquivo(), carregar(), chave_de(), definir(), _limpar(), _normalizar(), obter() (+8 more)

### Community 55 - "EntregaController"
Cohesion: 0.08
Nodes (22): P2P Architecture Documentation, _endereco_para_qr(), EntregaController, pyqtSlot, QObject, Nome do .txt gravado pela última chamada bem-sucedida de…, Gera o arquivo .txt do pedido de entrega e pede a impressão pela malha local…, Igual a enviarPedido, mas nunca tenta imprimir — usado pelo botão 'Lançar', que… (+14 more)

### Community 56 - "despesasCaixa.py"
Cohesion: 0.22
Nodes (15): apagar(), aplicar_edicao_remota(), _caminho_arquivo(), carregar(), editar(), listar_do_dia(), Registro persistido das DESPESAS do dia — dinheiro que sai do caixa para pagar…, Apaga um lançamento — tombstone genérico de services/rede/tombstones.py… (+7 more)

### Community 57 - "novo_id"
Cohesion: 0.15
Nodes (21): apagar(), aplicar_edicao_remota(), _caminho_arquivo(), carregar(), editar(), listar_do_dia(), Registro persistido dos pagamentos de diária a funcionários — dinheiro que sai…, Apaga um lançamento — tombstone genérico de services/rede/tombstones.py… (+13 more)

### Community 58 - "PrinterService"
Cohesion: 0.10
Nodes (14): BalcaoController, pyqtSlot, QObject, Nome do .txt gravado pela última chamada bem-sucedida de…, Gera o arquivo .txt do pedido e pede a impressão pela malha local `copias`…, Igual a enviarPedido, mas nunca tenta imprimir — usado pelo botão 'Lançar', que…, Dispara em segundo plano a busca pela impressora que esta máquina usaria para…, Monta o texto da comanda, grava o .txt e propaga para a rede local. Não imprime… (+6 more)

### Community 59 - "_aplicar_estilo_remoto"
Cohesion: 0.20
Nodes (8): _aplicar_estilo_remoto(), _mesclar_campos(), _mesclar_ordem(), _posicao_padrao(), Aplica localmente um estilo de impressão recebido de outra máquina (gossip ou…, Copia por cima de `destino` (já nos padrões) os valores válidos de…, Onde encaixar, dentro de `ordem`, a chave que ocupa `indice_padrao` em…, Valida `ordem_lida` (lista de chaves de CAMPOS_ORDENAVEIS) e devolve uma ordem…

### Community 60 - "baixaComandas.py"
Cohesion: 0.27
Nodes (12): _caminho_arquivo(), carregar(), esta_fechada(), mesclar(), purgar_apagadas(), Registro persistido das comandas que já receberam baixa — o que separa "a…, Descarta as baixas de comandas que foram apagadas de propósito — é daí que vem…, `{nome_arquivo: idEvento}` de todas as comandas com baixa, do ponto de vista… (+4 more)

### Community 61 - ".criarRede"
Cohesion: 0.14
Nodes (5): Força uma nova checagem da impressora local agora, em vez de esperar o próximo…, Primeira máquina: gera a chave e passa a ser a rede. Devolve "" ou o motivo de…, Abre os sockets e começa a anunciar/descobrir peers. Precisa ser chamado depois…, Liga o que só existe entre máquinas pareadas: discar para os peers, refazer…, Texto pronto pra tela, ou "" se está tudo certo pra subir. A falta de chave não…

### Community 62 - "splashInicializacao.py"
Cohesion: 0.16
Nodes (9): _desenhar(), iniciar(), Janela de carregamento mostrada enquanto o sistema abre. Por que existe. Entre…, Cria a QApplication do processo e mostra a tela de carregamento. Devolve (app,…, Objeto de mentira usado quando não deu para criar a janela (sem ambiente…, Troca a linha de status e redesenha na hora. O processEvents() é o ponto todo:…, Fecha a tela de carregamento. `janela` (a janela principal, uma QWindow do QML)…, _SemSplash (+1 more)

### Community 63 - "clientes.py"
Cohesion: 0.19
Nodes (20): Mesmo cuidado de `salvar_json` (temporário com PID + os.replace), para arquivo…, salvar_bytes(), aplicar_remoto(), buscar(), _caminho_arquivo(), carregar(), chave_de(), _coordenada() (+12 more)

### Community 64 - "Controllers (`controllers/`)"
Cohesion: 0.15
Nodes (12): Arquitetura em camadas, Como me ajudar, Contexto do projeto: PPGS System (pizzeria_system), Controllers (`controllers/`), Convenções e regras do repositório, Dados, Estado atual do trabalho (em 2026-09-24, branch `master`), Limitações conhecidas (+4 more)

### Community 65 - "windows.py"
Cohesion: 0.14
Nodes (20): _classificar_porta(), coletar_impressoras(), _coletar_nativo(), _coletar_via_powershell(), _consultar_status_esc_pos(), _consultar_status_esc_pos_tcp(), _executar_powershell(), _executavel_powershell() (+12 more)

### Community 66 - "caminhos.py"
Cohesion: 0.13
Nodes (21): carregar_json(), pasta_pedidos(), pasta_sincronizacao(), raiz_projeto(), Caminhos e leitura/escrita de JSON compartilhados pelos módulos de…, Pasta com as comandas (.txt) — a mesma que ConsultaController,…, `pedidos/.sync/`: metadados de sincronização (tombstones, índice de eventos,…, Devolve o dict gravado em `caminho`, ou {} se ele não existir ou estiver… (+13 more)

### Community 67 - "ClientesController"
Cohesion: 0.21
Nodes (6): ClientesController, pyqtSlot, QObject, O cadastro só funciona com a máquina numa rede (ver o topo)., O cliente deste telefone ({"telefone", "nome", "rua", "numero", "bairro",…, Cria ou sobrescreve o cliente com os dados da comanda de Entrega (cliente,…

### Community 68 - "dev_watch.py"
Cohesion: 0.24
Nodes (11): _arquivos_observados(), _encerrar_processo(), _esperar_workspace_da_janela(), _iniciar_processo(), main(), _mover_janela_para_workspace(), Roda main.py num subprocesso e reinicia automaticamente sempre que um arquivo…, Consulta o Hyprland pela janela do processo com esse pid e devolve o id do… (+3 more)

### Community 69 - "validacaoEndereco.py"
Cohesion: 0.19
Nodes (20): _fechar(), _float(), interpretar(), _limpo(), _mesma_cidade(), numero_valido(), _photon(), Validação do endereço de entrega pelo CEP, para o campo único de endereço da… (+12 more)

### Community 70 - "montadorIndiceRuas.py"
Cohesion: 0.23
Nodes (13): baixar_cidade(), _baixar_overpass(), _consulta_overpass(), consultar_correios(), _distancia_m(), ErroMontagem, _ponto(), Exception (+5 more)

### Community 71 - "redeQml.py"
Cohesion: 0.18
Nodes (9): pyqt6, pyqt6_qtqml, QNetworkAccessManager, QQmlNetworkAccessManagerFactory, FabricaRedeQml, _GerenciadorComUserAgent, instalar(), User-Agent nos pedidos de rede feitos pelo QML. O engine QML baixa imagens… (+1 more)

### Community 72 - "re"
Cohesion: 0.18
Nodes (11): dataclasses, pathlib, re, main(), Garante que nenhum QML fora de qml/estilo/ traga valor de estilo cru. Cor,…, verifica(), services_printer, eh_bematech_mp4200th() (+3 more)

### Community 73 - ".registrarEdicaoCaixa"
Cohesion: 0.23
Nodes (6): (codigo, cliente, valor) da comanda, lidos do .txt enquanto ele ainda existe.…, Anota que uma comanda JÁ FECHADA foi corrigida, para a linha sair no cupom de…, Anota que uma comanda JÁ FECHADA foi apagada de vez. Chamado por…, Grava e anuncia à malha — o que edição e exclusão têm em comum. O registro…, Anota uma edição ou exclusão de qualquer comanda — com baixa ou sem — para as…, AAAA-MM-DD" do dia da comanda, deduzido do nome do arquivo (que já embute a…

### Community 74 - "SessaoSegura"
Cohesion: 0.17
Nodes (7): enquadrar(), Prefixo de 4 bytes com o tamanho. Substitui o `json + b"\\n"` de antes: um…, Handshake e cifragem de UM socket entre máquinas pareadas. Simétrica: os dois…, True só depois que ESTA máquina verificou o HMAC do outro lado. Nenhuma…, Consome um frame. Durante o handshake devolve a lista de frames a mandar de…, HMAC da chave da malha sobre o transcrito inteiro. O rótulo do lado entra no…, SessaoSegura

### Community 75 - "._recalcular_e_cachear"
Cohesion: 0.14
Nodes (5): Reação a um "fechamento_atualizado" vindo de OUTRA máquina. A mensagem é…, Reação ao gossip "extra_lancado" — o caminho rápido, pra um lançamento novo OU…, Grava um lançamento novo OU aplica uma edição vinda de fora, conforme o id já…, Mesma lógica de _registrar_extra_aprendido: grava um lançamento novo OU aplica…, Recalcula o dia a partir das comandas desta máquina e atualiza o cache local.…

### Community 76 - "graphify"
Cohesion: 0.29
Nodes (6): Atualização antes de todo commit, Consultas, graphify, pizzeria_system, Quando o usuário já rodou `git add .`, Regras gerais

### Community 77 - "pareamento_teste.py"
Cohesion: 0.21
Nodes (10): ao_mudar_pareamento(), ao_pedido_de_entrada(), log(), Verifica o pareamento (entrada aprovada na rede) e o cadastro de clientes…, tick(), _argumentos_do_cadastro(), Verifica manualmente a sincronização do cadastro de usuários entre "máquinas" —…, Nome e código depois de --cadastrar, com padrão para quem esquecer. (+2 more)

### Community 78 - ".listarRascunhos"
Cohesion: 0.18
Nodes (7): pyqtSlot, Descarta o rascunho — pelo × do card, ou porque ele virou comanda (ver…, Soma o valor dos itens do rascunho. Mesma conta de…, Um resumo por rascunho, do mais recente para o mais antigo — só o que o card da…, O rascunho inteiro, pronto para repovoar o formulário. {} quando ele não existe…, Grava e devolve o id (novo, se o registro veio sem um). "" quando a gravação…, _valor_total_itens()

### Community 79 - "subprocess"
Cohesion: 0.25
Nodes (10): _avisar(), main(), _pythons_candidatos(), _raiz_do_projeto(), Lançador do sistema para Windows — é isto que vira o .exe de duplo clique. Não…, Pasta onde está o main.py. Procura ao lado do executável e nos diretórios acima…, Interpretadores a tentar, do mais específico para o mais genérico. O venv do…, Mostra o erro numa caixa do Windows; no resto, imprime. Sem isto, um .exe… (+2 more)

### Community 80 - "MontagemExtras.js"
Cohesion: 0.26
Nodes (9): adicionaisDaLinha(), bordaDaLinha(), _comoObjeto(), formatarMoeda(), gravarNaLinha(), precoDe(), precoMetadeDe(), valorAjustado() (+1 more)

### Community 81 - "_desenhar_modelo_rascunho"
Cohesion: 0.15
Nodes (12): modelo_impressao(), Disposição escolhida pra desenhar a comanda como imagem (ver…, _desenhar_modelo_rascunho(), _desenhar_separador(), _desenho_do_modelo(), _por_linha_fisica(), A comanda com a tabela de itens em três colunas, ou None quando este cupom não…, A comanda desenhada no modelo escolhido em Configurações, com o clássico como… (+4 more)

### Community 82 - "normalizar"
Cohesion: 0.24
Nodes (12): normalizar(), Minúsculas e sem acento, que é a forma comparável de tudo aqui. Sem isto,…, adicionar(), _limpar(), marcar_correios(), preparar(), _normalizar_bairro(), _normalizar_rua() (+4 more)

### Community 83 - "BarramentoEventos"
Cohesion: 0.24
Nodes (5): BarramentoEventos, `enviar_para_peers(evento, socket_excluido)` é injetado por quem monta este…, `callback(payload)` roda toda vez que um evento `tipo_evento` chega de outra…, Anuncia um evento novo, desta máquina, pra malha inteira. Não chama os…, Chamado por RedeService quando uma mensagem `{"tipo": "evento", ...}` chega de…

### Community 84 - "iconProvider.py"
Cohesion: 0.20
Nodes (7): collections, pyqt6_qtquick, QQuickImageProvider, qtawesome, IconProvider, Expõe os ícones do pacote `qtawesome` (Font Awesome, Material Design Icons…, urllib_parse

### Community 85 - "DestinoPedido.js"
Cohesion: 0.24
Nodes (3): acrescentarAoModelo(), _comoLinha(), inserirEmModelo()

### Community 86 - "_linhas_com_estilo"
Cohesion: 0.20
Nodes (7): _Estilo, _linhas_com_estilo(), Estado de estilo corrente durante a varredura de uma linha. Vive numa classe, e…, Liga/desliga o atributo que `comando` controla., Quebra uma linha do cupom em [(texto, negrito, sublinhado, reverso,…, O cupom inteiro como lista de linhas, cada uma já quebrada em trechos…, _trechos_da_linha()

### Community 87 - "._recalcular_maquina_impressora"
Cohesion: 0.17
Nodes (5): Se `id_maquina` ainda é uma candidata legítima agora (continua conectada — ou é…, Converte um nome de máquina (estável — ver _nome_maquina_fixada) no id_maquina…, Eleição "sticky com prioridade": entre máquinas do mesmo nível de prioridade,…, Fixa manualmente `nomeMaquina` como a máquina que imprime pra malha inteira…, Reação a um "impressora_fixada" publicado por OUTRA máquina — replica o mesmo…

### Community 89 - "._montar_recibo_extra"
Cohesion: 0.22
Nodes (4): FGTS.................... R$ 8,00" ocupando a linha inteira, com o valor…, ("23:26", "01/06/2026") a partir do "dd/mm/aaaa HH:MM:SS" gravado no lançamento…, Monta o recibo de pagamento de diária em bytes ESC/POS, pronto pra impressora,…, Pede a impressão do recibo pela malha local, igual a reimprimirComanda — o…

### Community 90 - "endereco_da_comanda"
Cohesion: 0.25
Nodes (9): Aceita tanto os bytes crus do arquivo quanto o texto já decodificado — quem…, _texto_limpo(), _cidade_da_pizzaria(), endereco_da_comanda(), A cidade da localização definida na tela Rede, para o Maps não achar a rua…, O endereço para o QR. Comanda com endereço validado traz a linha interna com o…, extrair_endereco_qr(), limpar_codigos_impressora() (+1 more)

### Community 91 - "fechamentoCache.py"
Cohesion: 0.33
Nodes (8): _caminho_arquivo(), carregar(), listar_dias(), _pasta_fechamentos(), Persistência do resumo de fechamento de caixa — um JSON por dia, na pasta de…, Resumo já salvo para `data_iso` ("AAAA-MM-DD"), ou None se esse dia nunca foi…, Datas ("AAAA-MM-DD") de todo dia já calculado/cacheado nesta máquina — usado…, salvar()

### Community 92 - "aquecer_familias"
Cohesion: 0.29
Nodes (6): aquecer_familias(), aquecer_icones_pagamento(), familias_locais(), As famílias de fonte que ESTA máquina tem — instaladas no sistema mais as…, Resolve, AGORA e na thread da interface, a fonte e o caractere de cada ícone de…, Lê a lista de fontes agora, pra que as threads de detecção e de impressão a…

### Community 93 - "._tentar_conectar_a_peer"
Cohesion: 0.25
Nodes (4): QHostAddress, Uma instância apareceu na rede (ver services/rede/descoberta.py). A descoberta…, Tenta de novo todo peer que a descoberta já anunciou mas com quem não há…, Abre uma conexão para CADA endereço anunciado pelo peer. Dois lados podem…

### Community 94 - "ResumoExtras.js"
Cohesion: 0.54
Nodes (7): comoObjeto(), extrasDoItem(), extrasDoSabor(), linhaBorda(), linhasDoItem(), saboresDe(), textoAdicional()

### Community 95 - "Texto.js"
Cohesion: 0.43
Nodes (6): capitalizarCampo(), capitalizarCampoFrase(), capitalizarFrase(), capitalizarNomes(), _maiusculaSegura(), _minusculaSegura()

### Community 96 - "BuscaComandas.js"
Cohesion: 0.43
Nodes (7): _achatar(), construirIndice(), _faixaPorPrefixo(), _limiteInferior(), _marcarPrefixo(), _ordenadoPor(), ordenar()

### Community 97 - "MontagemItem.js"
Cohesion: 0.46
Nodes (6): formatarMoeda(), montarAcai(), montarLanche(), montarPizza(), montarSimples(), _somaAdicionais()

### Community 98 - "Formato.js"
Cohesion: 0.43
Nodes (4): formatar(), moeda(), moedaCurta(), numero()

### Community 99 - "impressoraWindows.py"
Cohesion: 0.32
Nodes (11): _configurar_porta_serial(), _estado_nativo(), _executavel_powershell(), garantir_impressora_bematech(), _garantir_via_powershell(), _log(), _logar_resultado(), Automatiza, no Windows, a configuração da impressora térmica Bematech MP-4200… (+3 more)

### Community 100 - "TaxasBairroController"
Cohesion: 0.22
Nodes (5): pyqtSlot, QObject, R$ 8,00" quando o bairro tem taxa guardada; "" caso contrário., Guarda e publica a taxa do bairro. False quando não havia o que guardar (bairro…, TaxasBairroController

### Community 101 - "._aplicar_localizacao"
Cohesion: 0.29
Nodes (3): Adota `dados` como a localização da pizzaria e anuncia à malha. Qualquer…, Até quantos minutos de carro a pizzaria entrega (a zona de entrega do validador…, Última decisão vence, pelo relógio lógico: uma localização antiga chegando…

### Community 102 - "StatusInicializacaoService"
Cohesion: 0.33
Nodes (3): QObject, Exposto ao QML como `statusController`., StatusInicializacaoService

### Community 103 - "faixa_de_numeros"
Cohesion: 0.29
Nodes (7): faixa_de_numeros(), _fim_do_par(), A UF do estabelecimento. O campo "uf" vem do índice de ruas, que nem sempre já…, Onde termina "766/767" (o lado par e o ímpar da mesma altura): no 767. O ViaCEP…, (início, fim, lado) dos números que um CEP de rua atende, lido do "complemento"…, _sem_acento(), uf_da_localizacao()

### Community 104 - ".listarComandasAbertas"
Cohesion: 0.33
Nodes (3): Comandas de `data_iso` que ainda não receberam baixa, inteiras (com o cupom em…, As comandas de Entrega de `data_iso` ainda sem baixa, da mais recente pra mais…, Nomes de arquivo cuja data embutida bate com `data_iso`, sem abrir/ler o…

### Community 105 - "limpezaServidorAntigo.py"
Cohesion: 0.33
Nodes (8): _caminho_pid(), _eh_o_servidor(), executar(), _nome_do_processo(), _pasta_base(), Uma vez por abertura: encerra o ppgs_server que a versão anterior do sistema…, A mesma pasta que services/servidor/preparo.py usava., signal

### Community 108 - "redeService.py"
Cohesion: 0.12
Nodes (20): base64, json, pyqt6_qtnetwork, random, criar_descoberta(), enderecos_para_anunciar(), _ip_por_rota(), _ips_das_interfaces() (+12 more)

### Community 110 - "Paleta Forno Design System"
Cohesion: 0.50
Nodes (4): Food Color Palette Reference, Paleta Forno Design System, Caprasimo Font License, Figtree Font License

### Community 113 - "reservar"
Cohesion: 0.67
Nodes (3): reservar(), gerar_codigo_pedido(), Código de 7 caracteres pro cabeçalho da comanda impressa, a partir do `agora`…

## Knowledge Gaps
- **25 isolated node(s):** `pizzeria-system`, `Consultas`, `Atualização antes de todo commit`, `Quando o usuário já rodou `git add .``, `Regras gerais` (+20 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 969 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **11 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `protegido()` connect `protegido` to `SugestoesEnderecoService`, `cardapioService.py`, `ConsultaController`, `UsuariosController`, `SalaoController`, `sugestoesEndereco.py`, `ValidacaoEnderecoController`, `comandaEstiloService.py`, `pyqtSlot`, `EstatisticasController`, `QTcpSocket`, `pyqtSlot`, `os`, `._calcular_resumo_dia`, `EntregaController`, `PrinterService`, `.criarRede`, `Controllers (`controllers/`)`, `ClientesController`, `.registrarEdicaoCaixa`, `.listarRascunhos`, `._recalcular_maquina_impressora`, `._montar_recibo_extra`, `TaxasBairroController`, `.listarComandasAbertas`, `redeService.py`?**
  _High betweenness centrality (0.181) - this node is a cross-community bridge._
- **Why does `RedeService` connect `RedeService` to `Controllers (`controllers/`)`, `pyqtSlot`, `._aplicar_localizacao`, `pyqtProperty`, `redeService.py`, `.__init__`, `BarramentoEventos`, `protegido`, `._tentar_conectar_a_peer`, `.criarRede`, `._recalcular_maquina_impressora`, `PrinterService`, `._processar_mensagem`, `QTcpSocket`?**
  _High betweenness centrality (0.110) - this node is a cross-community bridge._
- **Why does `FechamentoController` connect `FechamentoController` to `Controllers (`controllers/`)`, `._montar_recibo_extra`, `os`, `.registrarEdicaoCaixa`, `._registrar_baixa_aprendida`, `._recalcular_e_cachear`, `._calcular_resumo_dia`, `._registrar_edicao_aprendida`, `.listarComandasAbertas`, `._aplicar_exclusao_extra`, `protegido`, `pyqtSlot`?**
  _High betweenness centrality (0.086) - this node is a cross-community bridge._
- **Are the 3 inferred relationships involving `protegido()` (e.g. with `decorar()` and `Nós mais conectados (pontos de maior impacto ao mexer)`) actually correct?**
  _`protegido()` has 3 INFERRED edges - model-reasoned connections that need verification._
- **Are the 4 inferred relationships involving `RedeService` (e.g. with `Nós mais conectados (pontos de maior impacto ao mexer)` and `Rede P2P (`services/rede/`), o coração do sistema`) actually correct?**
  _`RedeService` has 4 INFERRED edges - model-reasoned connections that need verification._
- **Are the 2 inferred relationships involving `FechamentoController` (e.g. with `Controllers (`controllers/`)` and `Nós mais conectados (pontos de maior impacto ao mexer)`) actually correct?**
  _`FechamentoController` has 2 INFERRED edges - model-reasoned connections that need verification._
- **What connects `pizzeria-system`, `Consultas`, `Atualização antes de todo commit` to the rest of the system?**
  _25 weakly-connected nodes found - possible documentation gaps or missing edges._