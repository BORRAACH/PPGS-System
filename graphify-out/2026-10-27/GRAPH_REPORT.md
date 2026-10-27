# Graph Report - pizzeria_system  (2026-10-25)

## Corpus Check
- 125 files · ~176,866 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 103 file(s) not represented in the graph (top: .qml 90, (none) 6, .ttf 5)

## Summary
- 2445 nodes · 5030 edges · 116 communities (106 shown, 10 thin omitted)
- Extraction: 99% EXTRACTED · 1% INFERRED · 0% AMBIGUOUS · INFERRED: 68 edges (avg confidence: 0.9)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `8ca5556a`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- SugestoesEnderecoService
- ErroSeguranca
- CardapioController
- atualizador.py
- ConsultaController
- UsuariosController
- indicePedidos.py
- cnefe.py
- SalaoController
- pasta_sincronizacao
- validacaoEndereco.py
- RedeService
- buscaCardapio.py
- comandaParserService.py
- indiceRuas.py
- historicoEnderecos.py
- Descoberta
- normalizar_endereco
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
- bootstrap.py
- QTcpSocket
- linux.py
- historicoEventos.py
- grafoRuas.py
- _tracos_de_texto
- usuarios.py
- _EscritaParaLog
- pyqtSlot
- seguranca.py
- preConfig.py
- pyqtProperty
- os
- RotasController
- printerService.py
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
- BalcaoController
- carregar_json
- extrasCaixa.py
- validar
- PrinterService
- baixaComandas.py
- .criarRede
- splashInicializacao.py
- clientes.py
- Contexto do projeto: PPGS System (pizzeria_system)
- windows.py
- novo_id
- sugestoes
- dev_watch.py
- semear_dados
- montadorIndiceRuas.py
- redeQml.py
- re
- .registrarEdicaoCaixa
- SessaoSegura
- ._recalcular_e_cachear
- graphify
- assinar_release.py
- RascunhosController
- iniciar.py
- MontagemExtras.js
- _desenhar_modelo_rascunho
- _photon
- BarramentoEventos
- iconProvider.py
- DestinoPedido.js
- _linhas_com_estilo
- ._recalcular_maquina_impressora
- instalar_captura_de_mensagens_qt
- ._montar_recibo_extra
- localizacaoServidor.py
- fechamentoCache.py
- linhas_espacamento_secoes
- ResumoExtras.js
- Texto.js
- BuscaComandas.js
- MontagemItem.js
- Formato.js
- impressoraWindows.py
- TaxasBairroController
- ._aplicar_localizacao
- StatusInicializacaoService
- .listarComandasAbertas
- limpezaServidorAntigo.py
- ._registrar_baixa_aprendida
- RoteiroLancamento.js
- rede/caminhos.py
- ._registrar_edicao_aprendida
- Paleta Forno Design System
- ._aplicar_exclusao_extra
- reservar
- _iniciar_rede
- Docker Compose Mesh Test
- pizzeria-system

## God Nodes (most connected - your core abstractions)
1. `protegido()` - 139 edges
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
- `Controllers (`controllers/`)` --references--> `ConsultaController`  [INFERRED]
  CONTEXTO_CLAUDE_WEB.md → controllers/consultaController.py
- `Nós mais conectados (pontos de maior impacto ao mexer)` --references--> `ConsultaController`  [INFERRED]
  CONTEXTO_CLAUDE_WEB.md → controllers/consultaController.py
- `Como o projeto funciona` --references--> `ConsultaController`  [INFERRED]
  README.md → controllers/consultaController.py

## Import Cycles
- 3-file cycle: `services/comandaEstiloService.py -> services/comandaImagemService.py -> services/comandaParserService.py -> services/comandaEstiloService.py`

## Hyperedges (group relationships)
- **Design System Foundations** — design_paleta_forno, qml_estilo_fontes_caprasimo, qml_estilo_fontes_figtree, design_food_color_palette [INFERRED 0.85]

## Communities (116 total, 10 thin omitted)

### Community 0 - "SugestoesEnderecoService"
Cohesion: 0.05
Nodes (29): _bairros_do_photon(), _features_de(), ordenar_bairros(), pyqtProperty, pyqtSlot, QObject, [(properties, coordinates)] do GeoJSON do Photon, ou None se a resposta não…, Ruas salvas nesta máquina (histórico e índice) que casam com `termo` —… (+21 more)

### Community 1 - "ErroSeguranca"
Cohesion: 0.18
Nodes (9): Rede P2P (`services/rede/`), o coração do sistema, ErroSeguranca, Exception, Falha de handshake ou de abertura de frame. Quem trata fecha o socket — nunca…, Entrega a chave da malha a uma máquina nova, com uma pessoa conferindo um…, Os dois lados já chegaram ao código (depois da revelação)., Consome a resposta e devolve o frame de revelação a mandar., Consome o pedido e devolve o frame de resposta a mandar. (+1 more)

### Community 2 - "CardapioController"
Cohesion: 0.06
Nodes (40): resumo(), tick(), _caminho_arquivo(), _caminho_versoes(), CardapioController, carregar(), _carregar_versoes(), _categoria() (+32 more)

### Community 3 - "atualizador.py"
Cohesion: 0.06
Nodes (51): _arquivos_cardapio_modificados_localmente(), _atualizar(), _branch_atual(), _caminho_relativo_cardapio(), checar_atualizacoes(), _commits_atras(), _desfazer_guarda_cardapio_local(), _eh_repositorio_git() (+43 more)

### Community 4 - "ConsultaController"
Cohesion: 0.06
Nodes (27): ConsultaController, pyqtSlot, QObject, Descarta os conflitos que a regra antiga gravou sem olhar conteúdo. Até aqui…, A "versão" de cada comanda é o id de linha do tempo dela MAIS a impressão…, Decide se vale puxar do peer a comanda `nome_arquivo`. Só o transporte decide…, A data mais antiga (como "AAAAMMDD") que ainda conta como recente. Mesma…, 20260731" -> "31/07/2026", o mesmo formato do cabeçalho do cupom (e o que… (+19 more)

### Community 5 - "UsuariosController"
Cohesion: 0.06
Nodes (24): pyqtSlot, QObject, Sem janela temporal, ao contrário de "extras"/"fechamento": um cadastro não é…, Reação ao gossip "usuario_alterado" — para um cadastro novo OU uma correção…, Grava um usuário aprendido de fora, venha ele do gossip ou da reconciliação —…, Todos os usuários, ordenados por nome, cada um com "duplicado": True quando…, Tudo que se sabe sobre uma pessoa do cadastro, para o popup que abre ao clicar…, Se as ações protegidas (imprimir, lançar, editar comanda fechada, apagar… (+16 more)

### Community 6 - "indicePedidos.py"
Cohesion: 0.08
Nodes (45): contextlib, pasta_pedidos(), Pasta com as comandas (.txt) — a mesma que ConsultaController,…, _calcular_impressao(), _caminho_conflitos(), _caminho_eventos(), _carregar(), carregar_conflitos() (+37 more)

### Community 7 - "cnefe.py"
Cohesion: 0.08
Nodes (44): collections, csv, io, bairros_da_rua(), baixar_e_montar(), buscar_ruas(), caminho_banco(), _carregado() (+36 more)

### Community 8 - "SalaoController"
Cohesion: 0.09
Nodes (23): _chave_item(), _item_sem_precos(), _itens_pendentes_cozinha(), _itens_reais(), pyqtSlot, QObject, Gerencia comandas de mesa (Salao.qml): diferente de Balcão/Entrega, uma comanda…, Todas as mesas abertas gravadas localmente, como dicts completos (não só o… (+15 more)

### Community 9 - "pasta_sincronizacao"
Cohesion: 0.09
Nodes (24): pasta_sincronizacao(), `pedidos/.sync/`: metadados de sincronização (tombstones, índice de eventos,…, Grava `dados` de forma atômica (temporário + os.replace). `compacto` é para…, salvar_json(), aplicar_remoto(), _bytes_da_senha(), _caminho_arquivo(), carregar() (+16 more)

### Community 10 - "validacaoEndereco.py"
Cohesion: 0.15
Nodes (16): _fim_do_par(), limite_entrega(), _mesma_cidade(), mesma_rua(), Validação do endereço de entrega pelo CEP, para o campo único de endereço da…, A mesma rua escrita de dois jeitos, com ou sem o tipo de via., A UF do estabelecimento. O campo "uf" vem do índice de ruas, que nem sempre já…, Os CEPs que o ViaCEP conhece para a rua na cidade. A resposta traz toda rua que… (+8 more)

### Community 11 - "RedeService"
Cohesion: 0.06
Nodes (15): QObject, Aprende reservas de número feitas em outra máquina. É este caminho — não a…, Quando um peer NOVO entra na malha (a quantidade aumentou, não só mudou),…, Anuncia `payload` (precisa ser serializável em JSON) pra malha inteira sob o…, Registra `callback(payload)` pra rodar sempre que um evento `tipo_evento`…, Anuncia um hash por dia, só dos dias dentro da janela de retenção. A janela…, As fontes da máquina que a malha está usando pra imprimir agora, pra alimentar…, Roda em thread própria (ver solicitar_impressao) — a impressão (spooler/CUPS)… (+7 more)

### Community 12 - "buscaCardapio.py"
Cohesion: 0.08
Nodes (39): analisar_item_comanda(), _aplicar_promocao(), aquecer(), _arquivo_promocao_do_dia(), _assinatura_dos_arquivos(), buscar(), _carregar_promocoes(), _detalhes_do_item() (+31 more)

### Community 13 - "comandaParserService.py"
Cohesion: 0.06
Nodes (42): campos_comparaveis(), comparar(), diferencas_entre(), _formatar(), Compara duas versões da MESMA comanda campo a campo, para dizer se elas são de…, Lista vira uma linha por elemento; o resto vira texto puro. É o que a tela…, Os campos cujo valor difere entre as duas versões, na ordem de ROTULOS (a mesma…, Atalho para os dois passos acima, que é como quem chama sempre usa. (+34 more)

### Community 14 - "indiceRuas.py"
Cohesion: 0.06
Nodes (61): bisect, pyqtProperty, pyqtSlot, QObject, TemaController, adicionar(), aplicar_montagem(), aplicar_remoto() (+53 more)

### Community 15 - "historicoEnderecos.py"
Cohesion: 0.12
Nodes (33): O termo digitado normalizado e, quando fica diferente, também com a abreviação…, termos_de_busca(), aplicar_remoto(), aprendido(), buscar_bairros(), buscar_ruas(), _caminho_arquivo(), carregar() (+25 more)

### Community 16 - "Descoberta"
Cohesion: 0.07
Nodes (18): criar_descoberta(), Descoberta, DescobertaBroadcast, DescobertaZeroconf, enderecos_para_anunciar(), _ip_por_rota(), _ips_das_interfaces(), QObject (+10 more)

### Community 17 - "normalizar_endereco"
Cohesion: 0.17
Nodes (18): bairros_equivalentes(), escolher_bairro(), normalizar_endereco(), palavras_distintivas(), Comparação de endereços e grafia formatada: reconhece que o endereço salvo…, Mesmo bairro escrito de dois jeitos: iguais depois de normalizar, ou as…, O candidato equivalente a `bairro`, "" se nenhum, None se mais de um (ambíguo).…, A grafia formatada de `bairro` para uma rua cujos bairros oficiais (Correios) e… (+10 more)

### Community 18 - "FechamentoController"
Cohesion: 0.07
Nodes (9): FechamentoController, QObject, Fechamento de caixa diário: soma o valor das comandas **fechadas**…, Payload deliberadamente vazio de números: quem recebe recalcula o dia com as…, Anuncia as baixas recentes. A janela recorta só o que é ANUNCIADO: o arquivo em…, Só puxa o que não existe aqui. O comparador padrão de…, Anuncia os pagamentos de diária recentes, na mesma janela do domínio…, Anuncia as alterações recentes, na mesma janela dos outros domínios do caixa:… (+1 more)

### Community 19 - "ValidacaoEnderecoController"
Cohesion: 0.06
Nodes (29): Arquitetura em camadas, Controllers (`controllers/`), Dados, Páginas QML (`qml/pages/`), ClientesController, pyqtSlot, QObject, O cadastro só funciona com a máquina numa rede (ver o topo). (+21 more)

### Community 20 - "protegido"
Cohesion: 0.10
Nodes (19): protegido(), decorar(), Decorador para os métodos expostos à QML (os @pyqtSlot dos controllers):…, Nós mais conectados (pontos de maior impacto ao mexer), ComandaEstiloController, _modalidade_do_exemplo(), ordem_secoes(), pyqtSlot (+11 more)

### Community 21 - "comandaEstiloService.py"
Cohesion: 0.06
Nodes (47): _aplicar_estilo_remoto(), atributos_campo(), _atributos_campo_padrao(), _caminho_arquivo(), _carregar(), _comando_tamanho_fonte(), _comando_tamanho_px(), fonte_impressao() (+39 more)

### Community 22 - "comandaImagemService.py"
Cohesion: 0.11
Nodes (29): aquecer_familias(), aquecer_icones_pagamento(), _comandos_raster(), desenhar_qr_endereco(), _desenhar_titulo(), _empacotar(), _estilo_de_campo(), familias_locais() (+21 more)

### Community 23 - "sys"
Cohesion: 0.08
Nodes (20): Simula apagar a comanda mais recente desta "máquina" (container), usando o…, Verifica manualmente a sincronização de Config/estilo_impressao.json entre…, Simula alguém tirando um pedido no Balcão desta "máquina" (container), usando o…, Verifica manualmente o histórico de eventos da malha…, Mostra quais outras "máquinas" (containers) esta instância enxerga na malha…, Fica rodando e imprimindo a letra desta "máquina" a cada 3s — usado só…, Verifica manualmente a sincronização da ORDEM dos campos da comanda…, ao_mudar_pareamento() (+12 more)

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

### Community 28 - "bootstrap.py"
Cohesion: 0.05
Nodes (80): argparse, aplicar_modo_raw_imediatamente(), configurar_fila_cups(), encontrar_dispositivo_tty(), encontrar_stty(), enviar_teste(), executar(), exigir_root() (+72 more)

### Community 29 - "QTcpSocket"
Cohesion: 0.16
Nodes (9): QTcpSocket, Um socket de pareamento fechou (ou foi fechado). Do lado que aprova, o pedido…, Devolve False quando o socket foi recusado e não se deve continuar lendo os…, Lado que PEDE: abre o pareamento com a máquina escolhida, por todos os…, Fecha e registra. O registro é o ponto: uma máquina recusada (hoje, na prática,…, Um socket que nunca chegou a conectar não emite `disconnected`, então…, Primeiro frame de uma conexão de entrada. Devolve False quando o socket foi…, Lado que APROVA: uma máquina sem chave pediu para entrar. (+1 more)

### Community 30 - "linux.py"
Cohesion: 0.14
Nodes (24): _classificar_porta(), coletar_impressoras(), _descricao_e_status(), _destino_padrao(), _dispositivos_conectados_agora(), _dispositivos_por_impressora(), _executar(), _extrair_porta() (+16 more)

### Community 31 - "historicoEventos.py"
Cohesion: 0.11
Nodes (26): tick(), aplicar(), _caminho(), _carregar(), contar_autorizacoes(), _detalhe_de(), listar(), obter() (+18 more)

### Community 32 - "grafoRuas.py"
Cohesion: 0.08
Nodes (25): heapq, baixar_elementos(), _caminho_cache(), comparar_entregas(), _consulta_overpass(), _distancia_m(), ErroRota, Grafo (+17 more)

### Community 33 - "_tracos_de_texto"
Cohesion: 0.25
Nodes (8): _espessura_do_traco(), _linhas_entre_itens(), A espessura do traço que substitui esta linha, ou None se ela é texto. As duas…, {índice: espessura} das linhas que o próprio texto do cupom já diz serem traço…, Índices das linhas lógicas que separam um item do outro dentro da tabela de…, {índice: espessura} de todos os traços do cupom — os que o texto já trazia e as…, _tracos_da_comanda(), _tracos_de_texto()

### Community 34 - "usuarios.py"
Cohesion: 0.15
Nodes (23): apagar(), aplicar_edicao_remota(), _caminho_arquivo(), carregar(), codigo_em_uso(), editar(), existe_algum(), listar() (+15 more)

### Community 35 - "_EscritaParaLog"
Cohesion: 0.15
Nodes (10): caminho_arquivo_log(), configurar_logging(), _EscritaParaLog, _instalar_captura_de_excecoes(), _ao_escapar_excecao(), _ao_escapar_excecao_em_thread(), _raiz_dados(), Faz toda exceção não tratada virar linha no log — e, no caso das que vêm de… (+2 more)

### Community 36 - "pyqtSlot"
Cohesion: 0.14
Nodes (7): pyqtSlot, Máquinas que anunciam impressora agora (esta + peers) — as opções disponíveis…, Info da impressora que a malha está usando pra imprimir agora (a máquina eleita…, Lado que APROVA: entrega a chave da rede à máquina que pediu. Quem chama já…, Máquinas atualmente conectadas na malha, mais recente primeiro., Histórico da malha para a tela de Rede, mais recente primeiro (ver…, Categorias existentes, para montar o filtro da tela sem repetir a lista no QML.

### Community 37 - "seguranca.py"
Cohesion: 0.10
Nodes (20): cryptography_hazmat_primitives, cryptography_hazmat_primitives_asymmetric_x25519, cryptography_hazmat_primitives_ciphers_aead, cryptography_hazmat_primitives_kdf_hkdf, hmac, secrets, cifrar(), raiz_dados() (+12 more)

### Community 38 - "preConfig.py"
Cohesion: 0.14
Nodes (21): _comandos_de_instalacao(), _configurar_estilo_qt_quick(), _dependencias_aplicaveis(), _dica_pacote_da_distro(), _em_ambiente_virtual(), _erro_de_import(), garantir_dependencias(), _garantir_modulo() (+13 more)

### Community 39 - "pyqtProperty"
Cohesion: 0.10
Nodes (9): pyqtProperty, Nome da máquina fixada manualmente (ver fixarImpressoraPrincipal), ou "" quando…, {"endereco", "descricao", "cidade", "lat", "lon", "origem", "idEvento"}, ou {}…, Máquinas pareadas que esta enxerga enquanto não tem chave., O pedido de entrada feito por esta máquina: {} ou {"id", "nome", "estado",…, Pedidos de outras máquinas esperando aprovação aqui., Quem guarda a chave local desta máquina (ver cofreLocal.protecao): a tela avisa…, Letra (A, B, C...) desta máquina por ordem de entrada dos PROCESSOS atualmente… (+1 more)

### Community 40 - "os"
Cohesion: 0.09
Nodes (38): base64, concurrent_futures, config, Onde ficam o código do sistema e onde ficam os dados dele. São duas raízes…, Redireciona toda a saída do app (stdout/stderr) — incluindo os inúmeros…, Cadastro de clientes da Entrega: busca por telefone (o autofill) e gravação,…, Estatísticas diárias (services/estatisticasService.py) para o "Fechar Caixa" e…, Os pedidos começados e não finalizados, para a faixa no topo de Balcão e… (+30 more)

### Community 41 - "RotasController"
Cohesion: 0.16
Nodes (7): pyqtProperty, pyqtSlot, QObject, Responde por comparacaoPronta (o dict de grafoRuas.comparar_entregas) ou…, Fechamento do sistema: um download em andamento não tenta o próximo servidor., Garante o grafo em memória, do cache ou baixado. Não faz nada se ele já está…, RotasController

### Community 42 - "printerService.py"
Cohesion: 0.15
Nodes (17): copy, dataclasses, services_printer, coletar_informacoes_impressoras(), _coletar_sem_cache(), enviar_para_impressora(), invalidar_cache(), Descarta o resultado guardado — a próxima coleta varre de novo. Para quem… (+9 more)

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
Cohesion: 0.14
Nodes (23): _formatar(), id_para_instante(), mais_novo(), True se `id_a` é estritamente mais recente que `id_b`. Único ponto de…, Monta um id "fictício" (desempate lógico zero, sem máquina) a partir de um…, _caminho_arquivo(), carregar(), _carregar_tudo() (+15 more)

### Community 47 - "cofreLocal.py"
Cohesion: 0.17
Nodes (22): _caminho_arquivo(), _caminho_marca(), _caminho_windows(), _chave_linux(), _chave_windows(), decifrar(), _decodificar(), ErroCofre (+14 more)

### Community 48 - "alteracoesComandas.py"
Cohesion: 0.21
Nodes (15): aplicar(), _caminho_arquivo(), carregar(), dias_com_alteracoes(), listar_do_dia(), obter(), Registro persistido de TODA edição e exclusão de comanda — com baixa ou sem —…, Grava uma alteração aprendida de outra máquina. Devolve o dia atingido quando… (+7 more)

### Community 49 - "sequenciaComandas.py"
Cohesion: 0.18
Nodes (17): _caminho_arquivo(), carregar(), dia(), dias_recentes(), _maior_numero(), mesclar_dia(), purgar_antigos(), Registro das reservas de número de comanda do dia — o que faz os dois últimos… (+9 more)

### Community 50 - "diagnosticar_impressora.py"
Cohesion: 0.15
Nodes (18): _executavel_powershell(), listar_impressoras(), log(), main(), _payload_teste(), _payload_teste_raster(), Diagnóstico da impressão térmica configurada (Bematech MP-4200 TH ou qualquer…, Loga cada impressora instalada no sistema operacional (nome, porta,… (+10 more)

### Community 51 - "_bloco_tabela_rascunho"
Cohesion: 0.12
Nodes (13): _bloco_tabela_rascunho(), _Celula, _colunas_rascunho(), _largura_da_coluna_valor(), Um pedaço de texto a desenhar num retângulo: o texto, a fonte dele e onde ele…, A altura que este texto ocupa na coluna, decidindo de passagem como ele vai…, (x, largura) de cada uma das três colunas, em dots, dada a largura já medida da…, + BACON (R$ 5,00)", e com o sabor no fim quando a pizza tem mais de um — senão,… (+5 more)

### Community 52 - "comandaTextoService.py"
Cohesion: 0.07
Nodes (40): _linhas_itens_producao(), Tabela de itens da comanda do pizzaiolo — mesma montagem de grupos de…, categoria_campo(), formatar_campo(), linhas_separador_antes(), Envolve `texto` com os comandos ESC/POS ligados/desligados conforme a…, Quantas linhas de traço ("-" * 40) entram ANTES de `campo` numa comanda em que…, Categoria de `campo` (ver CATEGORIA_CAMPO) — "" para uma chave desconhecida, o… (+32 more)

### Community 53 - "edicoesCaixa.py"
Cohesion: 0.19
Nodes (16): aplicar(), _caminho_arquivo(), carregar(), contar_do_usuario(), listar_do_dia(), obter(), Registro persistido das ALTERAÇÕES feitas em comandas que já receberam baixa —…, Grava uma alteração e devolve o id do registro. `quando` vem preenchido quando… (+8 more)

### Community 54 - "taxasBairro.py"
Cohesion: 0.25
Nodes (16): aplicar_remoto(), _caminho_arquivo(), carregar(), chave_de(), definir(), _limpar(), _normalizar(), obter() (+8 more)

### Community 55 - "BalcaoController"
Cohesion: 0.06
Nodes (30): P2P Architecture Documentation, BalcaoController, pyqtSlot, QObject, Nome do .txt gravado pela última chamada bem-sucedida de…, Gera o arquivo .txt do pedido e pede a impressão pela malha local `copias`…, Igual a enviarPedido, mas nunca tenta imprimir — usado pelo botão 'Lançar', que…, Dispara em segundo plano a busca pela impressora que esta máquina usaria para… (+22 more)

### Community 56 - "carregar_json"
Cohesion: 0.16
Nodes (16): carregar_json(), Devolve o dict gravado em `caminho`, ou {} se ele não existir ou estiver…, apagar(), aplicar_edicao_remota(), _caminho_arquivo(), carregar(), editar(), listar_do_dia() (+8 more)

### Community 57 - "extrasCaixa.py"
Cohesion: 0.22
Nodes (15): apagar(), aplicar_edicao_remota(), _caminho_arquivo(), carregar(), editar(), listar_do_dia(), Registro persistido dos pagamentos de diária a funcionários — dinheiro que sai…, Apaga um lançamento — tombstone genérico de services/rede/tombstones.py… (+7 more)

### Community 58 - "validar"
Cohesion: 0.19
Nodes (16): cep_da_rua(), cep_digitos(), _cep_util(), faixa_de_numeros(), formatar_cep(), _numero_na_faixa(), 12062-130" a partir de qualquer grafia com 8 dígitos; "" se não tiver., CEP com 8 dígitos. O final -000 NÃO é descartado: em Taubaté 12080-000 e… (+8 more)

### Community 59 - "PrinterService"
Cohesion: 0.23
Nodes (6): PrinterService, O caminho de texto, com uma exceção: o título da modalidade sai como imagem,…, O conteúdo sem os marcadores de tamanho exato (ver…, Envia `conteudo` (bytes crus, já formatados em ESC/POS) para a impressora…, Retorna a `InfoImpressora` configurada, ou None se não encontrada.…, O conteúdo pronto pra ir ao papel: a comanda desenhada como imagem, quando há…

### Community 60 - "baixaComandas.py"
Cohesion: 0.27
Nodes (12): _caminho_arquivo(), carregar(), esta_fechada(), mesclar(), purgar_apagadas(), Registro persistido das comandas que já receberam baixa — o que separa "a…, Descarta as baixas de comandas que foram apagadas de propósito — é daí que vem…, `{nome_arquivo: idEvento}` de todas as comandas com baixa, do ponto de vista… (+4 more)

### Community 61 - ".criarRede"
Cohesion: 0.09
Nodes (9): QHostAddress, Força uma nova checagem da impressora local agora, em vez de esperar o próximo…, Primeira máquina: gera a chave e passa a ser a rede. Devolve "" ou o motivo de…, Abre os sockets e começa a anunciar/descobrir peers. Precisa ser chamado depois…, Liga o que só existe entre máquinas pareadas: discar para os peers, refazer…, Texto pronto pra tela, ou "" se está tudo certo pra subir. A falta de chave não…, Uma instância apareceu na rede (ver services/rede/descoberta.py). A descoberta…, Tenta de novo todo peer que a descoberta já anunciou mas com quem não há… (+1 more)

### Community 62 - "splashInicializacao.py"
Cohesion: 0.16
Nodes (9): _desenhar(), iniciar(), Janela de carregamento mostrada enquanto o sistema abre. Por que existe. Entre…, Cria a QApplication do processo e mostra a tela de carregamento. Devolve (app,…, Objeto de mentira usado quando não deu para criar a janela (sem ambiente…, Troca a linha de status e redesenha na hora. O processEvents() é o ponto todo:…, Fecha a tela de carregamento. `janela` (a janela principal, uma QWindow do QML)…, _SemSplash (+1 more)

### Community 63 - "clientes.py"
Cohesion: 0.19
Nodes (20): Mesmo cuidado de `salvar_json` (temporário com PID + os.replace), para arquivo…, salvar_bytes(), aplicar_remoto(), buscar(), _caminho_arquivo(), carregar(), chave_de(), _coordenada() (+12 more)

### Community 64 - "Contexto do projeto: PPGS System (pizzeria_system)"
Cohesion: 0.25
Nodes (7): Como me ajudar, Contexto do projeto: PPGS System (pizzeria_system), Convenções e regras do repositório, Estado atual do trabalho (em 2026-09-24, branch `master`), Limitações conhecidas, O que é, Serviços de domínio (`services/`)

### Community 65 - "windows.py"
Cohesion: 0.13
Nodes (22): eh_bematech_mp4200th(), Reconhece a Bematech MP-4200 TH pelo nome/fabricante/modelo reportados pelo SO.…, _classificar_porta(), coletar_impressoras(), _coletar_nativo(), _coletar_via_powershell(), _consultar_status_esc_pos(), _consultar_status_esc_pos_tcp() (+14 more)

### Community 66 - "novo_id"
Cohesion: 0.17
Nodes (17): aplicar_remoto(), _caminho_arquivo(), carregar(), obter_dia(), Contagem manual de caixa por forma de pagamento (Cartão, Dinheiro, Pix), usada…, `{dataIso: {cartao, dinheiro, pix, idEvento}}` de todos os dias já contados…, O registro de `data_iso`, ou None se o dia nunca foi contado., Grava (sobrescrevendo) a contagem de `data_iso` e devolve o id da gravação.… (+9 more)

### Community 67 - "sugestoes"
Cohesion: 0.31
Nodes (11): interpretar(), _limpo(), numero_valido(), {rua, numero, bairro, cep, pistaCondominio} do que foi digitado: "Rua Goiás,…, Formato do ListaSugestoes: "nome" é a linha principal e "bairro" a de baixo; os…, As sugestões do histórico/índice de ruas (sem internet), com o número e as…, (sugestões, aviso): as locais primeiro, depois as do Photon na cidade do…, _sugestao() (+3 more)

### Community 68 - "dev_watch.py"
Cohesion: 0.24
Nodes (11): _arquivos_observados(), _encerrar_processo(), _esperar_workspace_da_janela(), _iniciar_processo(), main(), _mover_janela_para_workspace(), Roda main.py num subprocesso e reinicia automaticamente sempre que um arquivo…, Consulta o Hyprland pela janela do processo com esse pid e devolve o id do… (+3 more)

### Community 69 - "semear_dados"
Cohesion: 0.29
Nodes (7): codigo(), dados(), dados_separados(), Caminho dentro da pasta do código (somente leitura em produção)., Caminho dentro da pasta de dados da máquina (gravável)., Copia para a pasta de dados o que o código traz de série e ainda não existe lá.…, semear_dados()

### Community 70 - "montadorIndiceRuas.py"
Cohesion: 0.23
Nodes (13): baixar_cidade(), _baixar_overpass(), _consulta_overpass(), consultar_correios(), _distancia_m(), ErroMontagem, _ponto(), Exception (+5 more)

### Community 71 - "redeQml.py"
Cohesion: 0.18
Nodes (9): pyqt6, pyqt6_qtqml, QNetworkAccessManager, QQmlNetworkAccessManagerFactory, FabricaRedeQml, _GerenciadorComUserAgent, instalar(), User-Agent nos pedidos de rede feitos pelo QML. O engine QML baixa imagens… (+1 more)

### Community 72 - "re"
Cohesion: 0.50
Nodes (4): re, main(), Garante que nenhum QML fora de qml/estilo/ traga valor de estilo cru. Cor,…, verifica()

### Community 73 - ".registrarEdicaoCaixa"
Cohesion: 0.23
Nodes (6): (codigo, cliente, valor) da comanda, lidos do .txt enquanto ele ainda existe.…, Anota que uma comanda JÁ FECHADA foi corrigida, para a linha sair no cupom de…, Anota que uma comanda JÁ FECHADA foi apagada de vez. Chamado por…, Grava e anuncia à malha — o que edição e exclusão têm em comum. O registro…, Anota uma edição ou exclusão de qualquer comanda — com baixa ou sem — para as…, AAAA-MM-DD" do dia da comanda, deduzido do nome do arquivo (que já embute a…

### Community 74 - "SessaoSegura"
Cohesion: 0.15
Nodes (9): enquadrar(), ler_json(), Prefixo de 4 bytes com o tamanho. Substitui o `json + b"\\n"` de antes: um…, Frame em claro (abertura do handshake ou pareamento) como dict., Handshake e cifragem de UM socket entre máquinas pareadas. Simétrica: os dois…, True só depois que ESTA máquina verificou o HMAC do outro lado. Nenhuma…, Consome um frame. Durante o handshake devolve a lista de frames a mandar de…, HMAC da chave da malha sobre o transcrito inteiro. O rótulo do lado entra no… (+1 more)

### Community 75 - "._recalcular_e_cachear"
Cohesion: 0.14
Nodes (5): Reação a um "fechamento_atualizado" vindo de OUTRA máquina. A mensagem é…, Reação ao gossip "extra_lancado" — o caminho rápido, pra um lançamento novo OU…, Grava um lançamento novo OU aplica uma edição vinda de fora, conforme o id já…, Mesma lógica de _registrar_extra_aprendido: grava um lançamento novo OU aplica…, Recalcula o dia a partir das comandas desta máquina e atualiza o cache local.…

### Community 76 - "graphify"
Cohesion: 0.29
Nodes (6): Atualização antes de todo commit, Consultas, graphify, pizzeria_system, Quando o usuário já rodou `git add .`, Regras gerais

### Community 77 - "assinar_release.py"
Cohesion: 0.48
Nodes (6): _arquivos_do_app(), empacotar(), gerar_chaves(), main(), Empacota e assina uma release do sistema (usado pelo workflow de release, mas…, _sha256()

### Community 78 - "RascunhosController"
Cohesion: 0.19
Nodes (9): pyqtSlot, QObject, RascunhosController, Descarta o rascunho — pelo × do card, ou porque ele virou comanda (ver…, Soma o valor dos itens do rascunho. Mesma conta de…, Um resumo por rascunho, do mais recente para o mais antigo — só o que o card da…, O rascunho inteiro, pronto para repovoar o formulário. {} quando ele não existe…, Grava e devolve o id (novo, se o registro veio sem um). "" quando a gravação… (+1 more)

### Community 79 - "iniciar.py"
Cohesion: 0.22
Nodes (14): _avisar(), _executar_empacotado(), main(), _pasta_do_exe(), _pythons_candidatos(), _raiz_do_projeto(), Lançador do sistema para Windows — é isto que vira o .exe de duplo clique. Não…, Põe runtime.novo\\ no lugar de runtime\\ (preparado pelo bootstrap). A troca é… (+6 more)

### Community 80 - "MontagemExtras.js"
Cohesion: 0.26
Nodes (9): adicionaisDaLinha(), bordaDaLinha(), _comoObjeto(), formatarMoeda(), gravarNaLinha(), precoDe(), precoMetadeDe(), valorAjustado() (+1 more)

### Community 81 - "_desenhar_modelo_rascunho"
Cohesion: 0.09
Nodes (30): modelo_impressao(), Disposição escolhida pra desenhar a comanda como imagem (ver…, _altura_da_linha(), _desenhar_icone(), _desenhar_modelo_classico(), _desenhar_modelo_rascunho(), _desenhar_separador(), _desenho_do_modelo() (+22 more)

### Community 82 - "_photon"
Cohesion: 0.33
Nodes (6): _fechar(), _float(), _photon(), [(properties, [lon, lat])] do Photon, perto do estabelecimento., Resultado para uma falha inesperada (bug, não rede): o que foi digitado, com…, resultado_de_falha()

### Community 83 - "BarramentoEventos"
Cohesion: 0.18
Nodes (6): BarramentoEventos, `enviar_para_peers(evento, socket_excluido)` é injetado por quem monta este…, `callback(payload)` roda toda vez que um evento `tipo_evento` chega de outra…, Anuncia um evento novo, desta máquina, pra malha inteira. Não chama os…, Chamado por RedeService quando uma mensagem `{"tipo": "evento", ...}` chega de…, Inscreve um domínio de estado (pedidos, mesas, cardápio, fechamento...) na…

### Community 84 - "iconProvider.py"
Cohesion: 0.22
Nodes (6): pyqt6_qtquick, QQuickImageProvider, qtawesome, IconProvider, Expõe os ícones do pacote `qtawesome` (Font Awesome, Material Design Icons…, urllib_parse

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

### Community 90 - "localizacaoServidor.py"
Cohesion: 0.22
Nodes (12): math, _cidade_da_pizzaria(), A cidade da localização definida na tela Rede, para o Maps não achar a rua…, bbox(), _caminho_arquivo(), carregar(), _limite_entrega(), normalizar_registro() (+4 more)

### Community 91 - "fechamentoCache.py"
Cohesion: 0.33
Nodes (8): _caminho_arquivo(), carregar(), listar_dias(), _pasta_fechamentos(), Persistência do resumo de fechamento de caixa — um JSON por dia, na pasta de…, Resumo já salvo para `data_iso` ("AAAA-MM-DD"), ou None se esse dia nunca foi…, Datas ("AAAA-MM-DD") de todo dia já calculado/cacheado nesta máquina — usado…, salvar()

### Community 92 - "linhas_espacamento_secoes"
Cohesion: 0.50
Nodes (4): linhas_espacamento_secoes(), Lista de linhas vazias usada como espaçador entre seções da comanda…, linhas_modalidade(), O título que abre a comanda de pedido ("ENTREGA", centralizado) e o espaçamento…

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

### Community 104 - ".listarComandasAbertas"
Cohesion: 0.33
Nodes (3): Comandas de `data_iso` que ainda não receberam baixa, inteiras (com o cupom em…, As comandas de Entrega de `data_iso` ainda sem baixa, da mais recente pra mais…, Nomes de arquivo cuja data embutida bate com `data_iso`, sem abrir/ler o…

### Community 105 - "limpezaServidorAntigo.py"
Cohesion: 0.33
Nodes (8): _caminho_pid(), _eh_o_servidor(), executar(), _nome_do_processo(), _pasta_base(), Uma vez por abertura: encerra o ppgs_server que a versão anterior do sistema…, A mesma pasta que services/servidor/preparo.py usava., signal

### Community 108 - "rede/caminhos.py"
Cohesion: 0.18
Nodes (11): json, pyqt6_qtnetwork, Caminhos e leitura/escrita de JSON compartilhados pelos módulos de…, Acha as outras instâncias deste app rodando na rede local. Separado de…, _caminho_arquivo(), carregar_nome_fixado(), Persistência da escolha manual de qual máquina da malha imprime (ver…, Nome da máquina fixada manualmente como impressora principal, ou None se nunca… (+3 more)

### Community 110 - "Paleta Forno Design System"
Cohesion: 0.50
Nodes (4): Food Color Palette Reference, Paleta Forno Design System, Caprasimo Font License, Figtree Font License

### Community 113 - "reservar"
Cohesion: 0.67
Nodes (3): reservar(), gerar_codigo_pedido(), Código de 7 caracteres pro cabeçalho da comanda impressa, a partir do `agora`…

## Knowledge Gaps
- **25 isolated node(s):** `pizzeria-system`, `Consultas`, `Atualização antes de todo commit`, `Quando o usuário já rodou `git add .``, `Regras gerais` (+20 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 1001 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **10 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `protegido()` connect `protegido` to `SugestoesEnderecoService`, `ErroSeguranca`, `CardapioController`, `ConsultaController`, `UsuariosController`, `SalaoController`, `indiceRuas.py`, `ValidacaoEnderecoController`, `comandaEstiloService.py`, `pyqtSlot`, `EstatisticasController`, `QTcpSocket`, `pyqtSlot`, `os`, `._calcular_resumo_dia`, `BalcaoController`, `.criarRede`, `.registrarEdicaoCaixa`, `RascunhosController`, `._recalcular_maquina_impressora`, `._montar_recibo_extra`, `TaxasBairroController`, `.listarComandasAbertas`?**
  _High betweenness centrality (0.214) - this node is a cross-community bridge._
- **Why does `FechamentoController` connect `FechamentoController` to `._montar_recibo_extra`, `os`, `.registrarEdicaoCaixa`, `._registrar_baixa_aprendida`, `._recalcular_e_cachear`, `._calcular_resumo_dia`, `._registrar_edicao_aprendida`, `.listarComandasAbertas`, `._aplicar_exclusao_extra`, `ValidacaoEnderecoController`, `protegido`, `pyqtSlot`?**
  _High betweenness centrality (0.092) - this node is a cross-community bridge._
- **Why does `RedeService` connect `RedeService` to `ErroSeguranca`, `pyqtSlot`, `._aplicar_localizacao`, `pyqtProperty`, `os`, `._processar_mensagem`, `BarramentoEventos`, `protegido`, `.criarRede`, `._recalcular_maquina_impressora`, `PrinterService`, `QTcpSocket`?**
  _High betweenness centrality (0.084) - this node is a cross-community bridge._
- **Are the 3 inferred relationships involving `protegido()` (e.g. with `decorar()` and `Nós mais conectados (pontos de maior impacto ao mexer)`) actually correct?**
  _`protegido()` has 3 INFERRED edges - model-reasoned connections that need verification._
- **Are the 4 inferred relationships involving `RedeService` (e.g. with `Nós mais conectados (pontos de maior impacto ao mexer)` and `Rede P2P (`services/rede/`), o coração do sistema`) actually correct?**
  _`RedeService` has 4 INFERRED edges - model-reasoned connections that need verification._
- **Are the 2 inferred relationships involving `FechamentoController` (e.g. with `Controllers (`controllers/`)` and `Nós mais conectados (pontos de maior impacto ao mexer)`) actually correct?**
  _`FechamentoController` has 2 INFERRED edges - model-reasoned connections that need verification._
- **What connects `pizzeria-system`, `Consultas`, `Atualização antes de todo commit` to the rest of the system?**
  _25 weakly-connected nodes found - possible documentation gaps or missing edges._