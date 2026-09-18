# Graph Report - pizzeria_system  (2026-09-18)

## Corpus Check
- 119 files · ~168,695 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 99 file(s) not represented in the graph (top: .qml 87, (none) 6, .ttf 5)

## Summary
- 2271 nodes · 4617 edges · 122 communities (105 shown, 17 thin omitted)
- Extraction: 99% EXTRACTED · 1% INFERRED · 0% AMBIGUOUS · INFERRED: 35 edges (avg confidence: 0.86)
- Token cost: 158,955 input · 3,886 output

## Community Hubs (Navigation)
- Sugestões de Endereço
- Criptografia da Rede
- Serviço de Cardápio
- Atualizador e Mescla Cardápio
- Consulta de Comandas
- Controller de Usuários
- Índice de Pedidos
- Base CNEFE IBGE
- Controller do Salão
- Cofre Local e Clientes
- Validação de Endereço
- Malha P2P Gossip
- Busca no Cardápio
- Parser e Comparação Comandas
- Índice de Ruas
- Histórico de Endereços
- Descoberta de Peers
- Controllers Auxiliares
- Fechamento Sync Remoto
- Controller Validação Endereço
- Proteção de Slots QML
- Estilo da Comanda
- Imagem da Comanda
- Imports Stdlib Rede
- Fontes e Testes Sync
- Ações do Fechamento
- Estatísticas Diárias
- Anti-entropia e Eleição
- Senha do Dono
- Pareamento de Máquinas
- Impressoras no Linux
- Histórico de Eventos
- Grafo de Ruas Rotas
- Modelos de Desenho Comanda
- Cadastro de Usuários
- Configuração de Log
- Impressora Principal da Malha
- Requisições HTTP
- Pré-configuração do Ambiente
- Propriedades da Rede
- Controllers e Numeração
- Controller de Rotas
- Info de Impressoras
- Serviço de Estatísticas
- Recibo Fechamento Caixa
- Rascunhos de Pedido
- Tombstones de Exclusão
- Configurar Bematech
- Alterações de Comandas
- Sequência de Comandas
- Diagnóstico de Impressora
- Tabela do Rascunho
- Texto da Comanda
- Edições do Caixa
- Relógio e IDs
- Controller de Entrega
- Despesas do Caixa
- Extras do Caixa
- Controller do Balcão
- Equivalência de Bairros
- Baixa de Comandas
- Ativação da Malha
- Splash de Inicialização
- Reconciliação Caixa Remoto
- Montador Índice Ruas
- Impressoras no Windows
- Contagem do Caixa
- Controller de Clientes
- Dev Watch
- Testes de Pareamento
- Localização da Pizzaria
- Rede do QML
- Normalização de Ruas
- Registro Alterações Caixa
- Espaçamento de Seções
- Quebra e Pintura Linhas
- Printer Service
- Impressora Windows Bematech
- Controller de Rascunhos
- Lançador Windows
- Montagem de Extras JS
- Fontes de Impressão
- Tabelas de Texto
- Barramento de Eventos
- Provedor de Ícones
- Destino do Pedido JS
- Estado de Estilo
- Grafo e Caminhos
- Busca de Ruas
- Recibo de Extra
- Limpeza Servidor Antigo
- Cache de Fechamento
- Itens de Produção
- Conexão com Peers
- Resumo de Extras JS
- Capitalização de Texto JS
- Busca de Comandas JS
- Montagem de Item JS
- Formatação JS
- Endereço do QR
- Faixa de Números CEP
- Comandas Abertas do Dia
- Status de Inicialização
- Pedido Remoto Consulta
- Baixa Remota
- Edição de Caixa Remota
- Extra Apagado Remoto
- Roteiro de Lançamento JS
- Estilo Reconciliação
- Impressão Remota
- Paleta e Fontes
- Documento Paleta Forno
- Linha QR Endereço
- Espaçamento de Corte
- Modalidade do Exemplo
- Modelo de Impressão
- Ordem das Seções
- Arquitetura P2P Doc
- Teste Docker Malha
- Projeto pyproject

## God Nodes (most connected - your core abstractions)
1. `protegido()` - 131 edges
2. `RedeService` - 105 edges
3. `FechamentoController` - 81 edges
4. `SugestoesEnderecoService` - 40 edges
5. `ConsultaController` - 33 edges
6. `normalizar()` - 33 edges
7. `UsuariosController` - 32 edges
8. `normalizar_endereco()` - 27 edges
9. `ComandaEstiloController` - 26 edges
10. `SalaoController` - 25 edges

## Surprising Connections (you probably didn't know these)
- `Paleta Forno Design System` --semantically_similar_to--> `Food Color Palette Reference`  [INFERRED] [semantically similar]
  design/Paleta Forno.html → design/Food-Color-Palette-6-768x768.webp
- `BalcaoController` --uses--> `PrinterService`  [INFERRED]
  controllers/balcaoController.py → services/printerService.py
- `_payload_teste_raster()` --calls--> `para_raster()`  [EXTRACTED]
  Config/diagnosticar_impressora.py → services/comandaImagemService.py
- `listar_impressoras()` --calls--> `coletar_informacoes_impressoras()`  [EXTRACTED]
  Config/diagnosticar_impressora.py → services/printer/info.py
- `_tarefas_de_fundo()` --calls--> `listar_impressoras()`  [EXTRACTED]
  main.py → Config/diagnosticar_impressora.py

## Import Cycles
- 3-file cycle: `services/comandaEstiloService.py -> services/comandaImagemService.py -> services/comandaParserService.py -> services/comandaEstiloService.py`

## Hyperedges (group relationships)
- **Design System Foundations** — design_paleta_forno, qml_estilo_fontes_caprasimo, qml_estilo_fontes_figtree, design_food_color_palette [INFERRED 0.85]

## Communities (122 total, 17 thin omitted)

### Community 0 - "Sugestões de Endereço"
Cohesion: 0.05
Nodes (30): _bairros_do_photon(), _features_de(), ordenar_bairros(), pyqtProperty, pyqtSlot, QObject, [(properties, coordinates)] do GeoJSON do Photon, ou None se a resposta não…, Ruas salvas nesta máquina (histórico e índice) que casam com `termo` —… (+22 more)

### Community 1 - "Criptografia da Rede"
Cohesion: 0.06
Nodes (34): cryptography_hazmat_primitives, cryptography_hazmat_primitives_asymmetric_x25519, cryptography_hazmat_primitives_ciphers_aead, cryptography_hazmat_primitives_kdf_hkdf, _caminho_chave(), carregar_chave(), chave_indice_clientes(), _derivar() (+26 more)

### Community 2 - "Serviço de Cardápio"
Cohesion: 0.06
Nodes (41): resumo(), tick(), _caminho_arquivo(), _caminho_versoes(), CardapioController, carregar(), _carregar_versoes(), _categoria() (+33 more)

### Community 3 - "Atualizador e Mescla Cardápio"
Cohesion: 0.06
Nodes (51): _arquivos_cardapio_modificados_localmente(), _atualizar(), _branch_atual(), _caminho_relativo_cardapio(), checar_atualizacoes(), _commits_atras(), _desfazer_guarda_cardapio_local(), _eh_repositorio_git() (+43 more)

### Community 4 - "Consulta de Comandas"
Cohesion: 0.06
Nodes (25): ConsultaController, pyqtSlot, QObject, Descarta os conflitos que a regra antiga gravou sem olhar conteúdo. Até aqui…, A "versão" de cada comanda é o id de linha do tempo dela MAIS a impressão…, Decide se vale puxar do peer a comanda `nome_arquivo`. Só o transporte decide…, A data mais antiga (como "AAAAMMDD") que ainda conta como recente. Mesma…, 20260731" -> "31/07/2026", o mesmo formato do cabeçalho do cupom (e o que… (+17 more)

### Community 5 - "Controller de Usuários"
Cohesion: 0.06
Nodes (23): pyqtSlot, QObject, Sem janela temporal, ao contrário de "extras"/"fechamento": um cadastro não é…, Reação ao gossip "usuario_alterado" — para um cadastro novo OU uma correção…, Grava um usuário aprendido de fora, venha ele do gossip ou da reconciliação —…, Todos os usuários, ordenados por nome, cada um com "duplicado": True quando…, Tudo que se sabe sobre uma pessoa do cadastro, para o popup que abre ao clicar…, Se as ações protegidas (imprimir, lançar, editar comanda fechada, apagar… (+15 more)

### Community 6 - "Índice de Pedidos"
Cohesion: 0.07
Nodes (46): contextlib, pasta_pedidos(), raiz_projeto(), Pasta com as comandas (.txt) — a mesma que ConsultaController,…, _calcular_impressao(), _caminho_conflitos(), _caminho_eventos(), _carregar() (+38 more)

### Community 7 - "Base CNEFE IBGE"
Cohesion: 0.07
Nodes (45): csv, io, bairros_da_rua(), baixar_e_montar(), buscar_ruas(), caminho_banco(), _carregado(), casa() (+37 more)

### Community 8 - "Controller do Salão"
Cohesion: 0.09
Nodes (23): _chave_item(), _item_sem_precos(), _itens_pendentes_cozinha(), _itens_reais(), pyqtSlot, QObject, Gerencia comandas de mesa (Salao.qml): diferente de Balcão/Entrega, uma comanda…, Todas as mesas abertas gravadas localmente, como dicts completos (não só o… (+15 more)

### Community 9 - "Cofre Local e Clientes"
Cohesion: 0.10
Nodes (41): _caminho_arquivo(), _caminho_marca(), _caminho_windows(), _chave_linux(), _chave_windows(), cifrar(), decifrar(), _decodificar() (+33 more)

### Community 10 - "Validação de Endereço"
Cohesion: 0.11
Nodes (40): normalizar_endereco(), Forma comparável de rua ou bairro: sem caixa, acento e pontuação, e com as…, cep_digitos(), _cep_util(), _fechar(), _float(), formatar_cep(), interpretar() (+32 more)

### Community 11 - "Malha P2P Gossip"
Cohesion: 0.06
Nodes (15): QObject, Aprende reservas de número feitas em outra máquina. É este caminho — não a…, Quando um peer NOVO entra na malha (a quantidade aumentou, não só mudou),…, Anuncia `payload` (precisa ser serializável em JSON) pra malha inteira sob o…, Registra `callback(payload)` pra rodar sempre que um evento `tipo_evento`…, Inscreve um domínio de estado (pedidos, mesas, cardápio, fechamento...) na…, Anuncia um hash por dia, só dos dias dentro da janela de retenção. A janela…, As fontes da máquina que a malha está usando pra imprimir agora, pra alimentar… (+7 more)

### Community 12 - "Busca no Cardápio"
Cohesion: 0.08
Nodes (38): bisect, analisar_item_comanda(), _aplicar_promocao(), aquecer(), _arquivo_promocao_do_dia(), _assinatura_dos_arquivos(), buscar(), _carregar_promocoes() (+30 more)

### Community 13 - "Parser e Comparação Comandas"
Cohesion: 0.07
Nodes (35): campos_comparaveis(), comparar(), diferencas_entre(), _formatar(), Compara duas versões da MESMA comanda campo a campo, para dizer se elas são de…, Lista vira uma linha por elemento; o resto vira texto puro. É o que a tela…, Os campos cujo valor difere entre as duas versões, na ordem de ROTULOS (a mesma…, Atalho para os dois passos acima, que é como quem chama sempre usa. (+27 more)

### Community 14 - "Índice de Ruas"
Cohesion: 0.11
Nodes (36): aplicar_montagem(), aplicar_remoto(), base(), bloco_da_chave(), _caminho_arquivo(), carregado(), _carregar(), chaves_consultadas() (+28 more)

### Community 15 - "Histórico de Endereços"
Cohesion: 0.12
Nodes (33): O termo digitado normalizado e, quando fica diferente, também com a abreviação…, termos_de_busca(), aplicar_remoto(), aprendido(), buscar_bairros(), buscar_ruas(), _caminho_arquivo(), carregar() (+25 more)

### Community 16 - "Descoberta de Peers"
Cohesion: 0.09
Nodes (10): Descoberta, DescobertaBroadcast, DescobertaZeroconf, QObject, Interface comum das estratégias de descoberta. Emite `peerDescoberto` para cada…, Começa a anunciar esta instância e a procurar as outras. `porta_tcp` é a porta…, A máquina entrou numa rede: o anúncio passa a dizer isso, para as pareadas…, Descoberta por mDNS/DNS-SD: anuncia esta instância como um serviço `_pizzaria-… (+2 more)

### Community 17 - "Controllers Auxiliares"
Cohesion: 0.12
Nodes (22): concurrent_futures, Cadastro de clientes da Entrega: busca por telefone (o autofill) e gravação,…, Estatísticas diárias (services/estatisticasService.py) para o "Fechar Caixa" e…, QObject, RascunhosController, Os pedidos começados e não finalizados, para a faixa no topo de Balcão e…, Comparação de rotas de entrega da tela Mapa (qml/pages/mapa/Maps.qml): com a…, Validação do endereço de entrega (qml/components/DeliveryAddressValidator.qml).… (+14 more)

### Community 18 - "Fechamento Sync Remoto"
Cohesion: 0.07
Nodes (9): FechamentoController, QObject, Fechamento de caixa diário: soma o valor das comandas **fechadas**…, Payload deliberadamente vazio de números: quem recebe recalcula o dia com as…, Anuncia as baixas recentes. A janela recorta só o que é ANUNCIADO: o arquivo em…, Só puxa o que não existe aqui. O comparador padrão de…, Anuncia os pagamentos de diária recentes, na mesma janela do domínio…, Anuncia as alterações recentes, na mesma janela dos outros domínios do caixa:… (+1 more)

### Community 19 - "Controller Validação Endereço"
Cohesion: 0.10
Nodes (15): pyqtSlot, QObject, A sugestão da casa `numero` da `rua`: a da última comanda para ela, senão a do…, {rua, numero, bairro, pistaCondominio} do texto livre: o Enter sem escolher…, Síncrono, a cada tecla: histórico e índice de ruas desta máquina., Locais + Photon, numa thread. Responde por sugestoesProntas., Valida a sugestão escolhida com o número do campo. Responde por validacaoPronta…, Mesma validação, partindo do CEP digitado pelo atendente. (+7 more)

### Community 20 - "Proteção de Slots QML"
Cohesion: 0.12
Nodes (14): protegido(), decorar(), Decorador para os métodos expostos à QML (os @pyqtSlot dos controllers):…, ComandaEstiloController, pyqtSlot, QObject, Ponte pra tela de Configurações (QML) ler/gravar o estilo acima., Catálogo pro seletor de fonte da comanda: a opção padrão (imprimir em texto,… (+6 more)

### Community 21 - "Estilo da Comanda"
Cohesion: 0.12
Nodes (26): _aplicar_estilo_remoto(), atributos_campo(), _atributos_campo_padrao(), _caminho_arquivo(), _carregar(), _herdar_estilo_do_nome_do_item(), _limitar_linhas_separador(), _mesclar_ajustes() (+18 more)

### Community 22 - "Imagem da Comanda"
Cohesion: 0.11
Nodes (29): aquecer_familias(), aquecer_icones_pagamento(), _comandos_raster(), desenhar_qr_endereco(), _desenhar_titulo(), _empacotar(), _estilo_de_campo(), familias_locais() (+21 more)

### Community 23 - "Imports Stdlib Rede"
Cohesion: 0.09
Nodes (24): base64, hashlib, json, pyqt6_qtnetwork, random, Caminhos e leitura/escrita de JSON compartilhados pelos módulos de…, criar_descoberta(), enderecos_para_anunciar() (+16 more)

### Community 24 - "Fontes e Testes Sync"
Cohesion: 0.09
Nodes (15): Registra as fontes embarcadas do app e define a Figtree como fonte padrão. Por…, Verifica manualmente a sincronização do cardápio entre "máquinas", em especial…, Verifica manualmente a sincronização de Config/estilo_impressao.json entre…, Simula alguém tirando um pedido no Balcão desta "máquina" (container), usando o…, Verifica manualmente o histórico de eventos da malha…, Mostra quais outras "máquinas" (containers) esta instância enxerga na malha…, Fica rodando e imprimindo a letra desta "máquina" a cada 3s — usado só…, Verifica manualmente a sincronização da ORDEM dos campos da comanda… (+7 more)

### Community 25 - "Ações do Fechamento"
Cohesion: 0.09
Nodes (14): _hoje_iso(), pyqtSlot, Se o resumo em cache foi gravado por uma versão do app que já montava tudo que…, Manda a comanda pra impressora exatamente como ela está em disco, `copias`…, Fecha a comanda: a partir daqui ela conta no caixa do dia. Não há operação…, Lança um pagamento de diária no dia `data_iso` e devolve o registro gravado…, Corrige o nome/valor de um pagamento de diária já lançado — mesmo id, mesma…, Apaga um pagamento de diária já lançado (ver… (+6 more)

### Community 26 - "Estatísticas Diárias"
Cohesion: 0.12
Nodes (13): EstatisticasController, trabalho(), _hoje_iso(), pyqtSlot, QObject, As alterações do dia. As correções de caixa gravadas antes de…, Monta e grava `data_iso`. Devolve as estatísticas gravadas., Chamado pelo "Fechar Caixa": grava o dia e avisa as outras máquinas. (+5 more)

### Community 27 - "Anti-entropia e Eleição"
Cohesion: 0.09
Nodes (8): Ponte entre BarramentoEventos e os sockets reais: manda `evento` pra todo peer…, Um ciclo de anti-entropy: monta o resumo atual de cada domínio registrado e…, Compara o resumo recebido de um peer com o estado local de cada domínio: aplica…, Se `id_maquina` ainda é uma candidata legítima agora (continua conectada — ou é…, Converte um nome de máquina (estável — ver _nome_maquina_fixada) no id_maquina…, Eleição "sticky com prioridade": entre máquinas do mesmo nível de prioridade,…, Chamado ao processar o handshake "identificar" de um peer que acabou de…, Reação a um "impressora_fixada" publicado por OUTRA máquina — replica o mesmo…

### Community 28 - "Senha do Dono"
Cohesion: 0.12
Nodes (24): hmac, secrets, aplicar_remoto(), _bytes_da_senha(), _caminho_arquivo(), carregar(), conferir(), definida() (+16 more)

### Community 29 - "Pareamento de Máquinas"
Cohesion: 0.16
Nodes (9): QTcpSocket, Um socket de pareamento fechou (ou foi fechado). Do lado que aprova, o pedido…, Devolve False quando o socket foi recusado e não se deve continuar lendo os…, Lado que PEDE: abre o pareamento com a máquina escolhida, por todos os…, Fecha e registra. O registro é o ponto: uma máquina recusada (hoje, na prática,…, Um socket que nunca chegou a conectar não emite `disconnected`, então…, Primeiro frame de uma conexão de entrada. Devolve False quando o socket foi…, Lado que APROVA: uma máquina sem chave pediu para entrar. (+1 more)

### Community 30 - "Impressoras no Linux"
Cohesion: 0.14
Nodes (24): _classificar_porta(), coletar_impressoras(), _descricao_e_status(), _destino_padrao(), _dispositivos_conectados_agora(), _dispositivos_por_impressora(), _executar(), _extrair_porta() (+16 more)

### Community 31 - "Histórico de Eventos"
Cohesion: 0.14
Nodes (22): tick(), aplicar(), _caminho(), _carregar(), contar_autorizacoes(), _detalhe_de(), listar(), obter() (+14 more)

### Community 32 - "Grafo de Ruas Rotas"
Cohesion: 0.12
Nodes (21): heapq, baixar_elementos(), _caminho_cache(), comparar_entregas(), _consulta_overpass(), _distancia_m(), ErroRota, ler_cache() (+13 more)

### Community 33 - "Modelos de Desenho Comanda"
Cohesion: 0.11
Nodes (24): _altura_da_linha(), _desenhar_modelo_classico(), _desenhar_modelo_rascunho(), _desenho_do_modelo(), _espessura_do_traco(), _icones_da_comanda(), _linhas_entre_itens(), _por_linha_fisica() (+16 more)

### Community 34 - "Cadastro de Usuários"
Cohesion: 0.15
Nodes (23): apagar(), aplicar_edicao_remota(), _caminho_arquivo(), carregar(), codigo_em_uso(), editar(), existe_algum(), listar() (+15 more)

### Community 35 - "Configuração de Log"
Cohesion: 0.11
Nodes (17): caminho_arquivo_log(), configurar_logging(), _EscritaParaLog, _instalar_captura_de_excecoes(), _ao_escapar_excecao(), _ao_escapar_excecao_em_thread(), instalar_captura_de_mensagens_qt(), _raiz_projeto() (+9 more)

### Community 36 - "Impressora Principal da Malha"
Cohesion: 0.09
Nodes (11): pyqtSlot, Máquinas que anunciam impressora agora (esta + peers) — as opções disponíveis…, Fixa manualmente `nomeMaquina` como a máquina que imprime pra malha inteira…, Info da impressora que a malha está usando pra imprimir agora (a máquina eleita…, Adota `dados` como a localização da pizzaria e anuncia à malha. Qualquer…, Até quantos minutos de carro a pizzaria entrega (a zona de entrega do validador…, Última decisão vence, pelo relógio lógico: uma localização antiga chegando…, Lado que APROVA: entrega a chave da rede à máquina que pediu. Quem chama já… (+3 more)

### Community 37 - "Requisições HTTP"
Cohesion: 0.11
Nodes (19): certifi, gzip, baixar_arquivo(), _corpo(), ErroRequisicao, obter_json(), obter_texto(), Exception (+11 more)

### Community 38 - "Pré-configuração do Ambiente"
Cohesion: 0.14
Nodes (21): _comandos_de_instalacao(), _configurar_estilo_qt_quick(), _dependencias_aplicaveis(), _dica_pacote_da_distro(), _em_ambiente_virtual(), _erro_de_import(), garantir_dependencias(), _garantir_modulo() (+13 more)

### Community 39 - "Propriedades da Rede"
Cohesion: 0.10
Nodes (9): pyqtProperty, Nome da máquina fixada manualmente (ver fixarImpressoraPrincipal), ou "" quando…, {"endereco", "descricao", "cidade", "lat", "lon", "origem", "idEvento"}, ou {}…, Máquinas pareadas que esta enxerga enquanto não tem chave., O pedido de entrada feito por esta máquina: {} ou {"id", "nome", "estado",…, Pedidos de outras máquinas esperando aprovação aqui., Quem guarda a chave local desta máquina (ver cofreLocal.protecao): a tela avisa…, Letra (A, B, C...) desta máquina por ordem de entrada dos PROCESSOS atualmente… (+1 more)

### Community 40 - "Controllers e Numeração"
Cohesion: 0.19
Nodes (11): Cadastro de usuários e o guarda das ações destrutivas. Duas responsabilidades…, datetime, Simula apagar a comanda mais recente desta "máquina" (container), usando o…, Reserva um número de comanda nesta "máquina" (container) e mostra o registro de…, reservar(), os, gerar_codigo_pedido(), Código curto impresso no cabeçalho de cada comanda (ver… (+3 more)

### Community 41 - "Controller de Rotas"
Cohesion: 0.16
Nodes (7): pyqtProperty, pyqtSlot, QObject, Responde por comparacaoPronta (o dict de grafoRuas.comparar_entregas) ou…, Fechamento do sistema: um download em andamento não tenta o próximo servidor., Garante o grafo em memória, do cache ou baixado. Não faz nada se ele já está…, RotasController

### Community 42 - "Info de Impressoras"
Cohesion: 0.17
Nodes (15): dataclasses, re, services_printer, coletar_informacoes_impressoras(), enviar_para_impressora(), Envia `conteudo` (bytes crus, já formatados em ESC/POS) para a fila de…, Coleta as impressoras instaladas no sistema operacional atual. Detecta…, _imprimir_relatorio() (+7 more)

### Community 43 - "Serviço de Estatísticas"
Cohesion: 0.16
Nodes (19): agregar(), _caminho(), carregar(), _centavos(), data_valida(), datas_do_periodo(), _hora(), listar_dias() (+11 more)

### Community 44 - "Recibo Fechamento Caixa"
Cohesion: 0.12
Nodes (9): fmt(), {"dinheiro", "pix", "cartao"} com a soma de `comandas` (a lista já filtrada de…, Bloco "ALTERAÇÕES APÓS A BAIXA" do cupom: uma entrada por comanda já fechada…, Monta, em bytes ESC/POS, o cupom-resumo impresso ao clicar "Fechar Caixa":…, Imprime o cupom-resumo do dia (ver _montar_recibo_fechamento). Chamado só pelo…, Uma comanda qualquer do disco, no mesmo formato de listarComandasAbertas mais o…, Abre uma comanda do dia e extrai dela os campos de cabeçalho que tanto o resumo…, Os itens do pedido de volta a partir do cupom já lido (desfaz… (+1 more)

### Community 45 - "Rascunhos de Pedido"
Cohesion: 0.19
Nodes (18): apagar(), _caminho(), _ler(), listar(), _normalizar_id(), obter(), pasta(), purgar_antigos() (+10 more)

### Community 46 - "Tombstones de Exclusão"
Cohesion: 0.19
Nodes (18): _caminho_arquivo(), carregar(), _carregar_tudo(), mesclar(), _migrar_formato_antigo(), _migrar_valor_antigo(), purgar_antigos(), Registro persistido de exclusões ("tombstones") para os domínios de… (+10 more)

### Community 47 - "Configurar Bematech"
Cohesion: 0.27
Nodes (17): aplicar_modo_raw_imediatamente(), configurar_fila_cups(), encontrar_dispositivo_tty(), encontrar_stty(), enviar_teste(), executar(), exigir_root(), garantir_cups_instalado() (+9 more)

### Community 48 - "Alterações de Comandas"
Cohesion: 0.18
Nodes (17): aplicar(), _caminho_arquivo(), carregar(), dias_com_alteracoes(), listar_do_dia(), obter(), Registro persistido de TODA edição e exclusão de comanda — com baixa ou sem —…, Grava uma alteração aprendida de outra máquina. Devolve o dia atingido quando… (+9 more)

### Community 49 - "Sequência de Comandas"
Cohesion: 0.18
Nodes (17): _caminho_arquivo(), carregar(), dia(), dias_recentes(), _maior_numero(), mesclar_dia(), purgar_antigos(), Registro das reservas de número de comanda do dia — o que faz os dois últimos… (+9 more)

### Community 50 - "Diagnóstico de Impressora"
Cohesion: 0.18
Nodes (16): argparse, config, _executavel_powershell(), listar_impressoras(), log(), main(), _payload_teste(), _payload_teste_raster() (+8 more)

### Community 51 - "Tabela do Rascunho"
Cohesion: 0.12
Nodes (13): _bloco_tabela_rascunho(), _Celula, _colunas_rascunho(), _largura_da_coluna_valor(), Um pedaço de texto a desenhar num retângulo: o texto, a fonte dele e onde ele…, A altura que este texto ocupa na coluna, decidindo de passagem como ele vai…, (x, largura) de cada uma das três colunas, em dots, dada a largura já medida da…, + BACON (R$ 5,00)", e com o sabor no fim quando a pizza tem mais de um — senão,… (+5 more)

### Community 52 - "Texto da Comanda"
Cohesion: 0.18
Nodes (16): _como_lista_de_dicts(), dividir_sabores(), _extras_adicionais(), _formatar_borda(), item_preenchido(), _linhas_de_list_model(), montar_grupos(), Montagem do texto de comandas (tabela de itens, valores) compartilhada por… (+8 more)

### Community 53 - "Edições do Caixa"
Cohesion: 0.19
Nodes (16): aplicar(), _caminho_arquivo(), carregar(), contar_do_usuario(), listar_do_dia(), obter(), Registro persistido das ALTERAÇÕES feitas em comandas que já receberam baixa —…, Grava uma alteração e devolve o id do registro. `quando` vem preenchido quando… (+8 more)

### Community 54 - "Relógio e IDs"
Cohesion: 0.18
Nodes (16): _analisar(), _formatar(), id_para_instante(), instante_do_id(), mais_novo(), _maquina_local(), _microssegundos_agora(), novo_id() (+8 more)

### Community 55 - "Controller de Entrega"
Cohesion: 0.17
Nodes (10): _endereco_para_qr(), EntregaController, pyqtSlot, QObject, Nome do .txt gravado pela última chamada bem-sucedida de…, Gera o arquivo .txt do pedido de entrega e pede a impressão pela malha local…, Igual a enviarPedido, mas nunca tenta imprimir — usado pelo botão 'Lançar', que…, Conta o endereço da comanda no histórico que alimenta as sugestões da Entrega… (+2 more)

### Community 56 - "Despesas do Caixa"
Cohesion: 0.22
Nodes (15): apagar(), aplicar_edicao_remota(), _caminho_arquivo(), carregar(), editar(), listar_do_dia(), Registro persistido das DESPESAS do dia — dinheiro que sai do caixa para pagar…, Apaga um lançamento — tombstone genérico de services/rede/tombstones.py… (+7 more)

### Community 57 - "Extras do Caixa"
Cohesion: 0.22
Nodes (15): apagar(), aplicar_edicao_remota(), _caminho_arquivo(), carregar(), editar(), listar_do_dia(), Registro persistido dos pagamentos de diária a funcionários — dinheiro que sai…, Apaga um lançamento — tombstone genérico de services/rede/tombstones.py… (+7 more)

### Community 58 - "Controller do Balcão"
Cohesion: 0.18
Nodes (8): BalcaoController, pyqtSlot, QObject, Nome do .txt gravado pela última chamada bem-sucedida de…, Gera o arquivo .txt do pedido e pede a impressão pela malha local `copias`…, Igual a enviarPedido, mas nunca tenta imprimir — usado pelo botão 'Lançar', que…, Dispara em segundo plano a busca pela impressora que esta máquina usaria para…, Monta o texto da comanda, grava o .txt e propaga para a rede local. Não imprime…

### Community 59 - "Equivalência de Bairros"
Cohesion: 0.16
Nodes (14): bairros_equivalentes(), palavras_distintivas(), Mesmo bairro escrito de dois jeitos: iguais depois de normalizar, ou as…, ordenar_enderecos(), do_bairro(), formatada(), uma(), Concatena os grupos na ordem dada, sem repetir item (pela `chave`, que compara… (+6 more)

### Community 60 - "Baixa de Comandas"
Cohesion: 0.22
Nodes (14): _caminho_arquivo(), carregar(), esta_fechada(), mesclar(), purgar_apagadas(), Registro persistido das comandas que já receberam baixa — o que separa "a…, Descarta as baixas de comandas que foram apagadas de propósito — é daí que vem…, `{nome_arquivo: idEvento}` de todas as comandas com baixa, do ponto de vista… (+6 more)

### Community 61 - "Ativação da Malha"
Cohesion: 0.14
Nodes (5): Força uma nova checagem da impressora local agora, em vez de esperar o próximo…, Primeira máquina: gera a chave e passa a ser a rede. Devolve "" ou o motivo de…, Abre os sockets e começa a anunciar/descobrir peers. Precisa ser chamado depois…, Liga o que só existe entre máquinas pareadas: discar para os peers, refazer…, Texto pronto pra tela, ou "" se está tudo certo pra subir. A falta de chave não…

### Community 62 - "Splash de Inicialização"
Cohesion: 0.16
Nodes (9): _desenhar(), iniciar(), Janela de carregamento mostrada enquanto o sistema abre. Por que existe. Entre…, Cria a QApplication do processo e mostra a tela de carregamento. Devolve (app,…, Objeto de mentira usado quando não deu para criar a janela (sem ambiente…, Troca a linha de status e redesenha na hora. O processEvents() é o ponto todo:…, Fecha a tela de carregamento. `janela` (a janela principal, uma QWindow do QML)…, _SemSplash (+1 more)

### Community 63 - "Reconciliação Caixa Remoto"
Cohesion: 0.14
Nodes (5): Reação a um "fechamento_atualizado" vindo de OUTRA máquina. A mensagem é…, Reação ao gossip "extra_lancado" — o caminho rápido, pra um lançamento novo OU…, Grava um lançamento novo OU aplica uma edição vinda de fora, conforme o id já…, Mesma lógica de _registrar_extra_aprendido: grava um lançamento novo OU aplica…, Recalcula o dia a partir das comandas desta máquina e atualiza o cache local.…

### Community 64 - "Montador Índice Ruas"
Cohesion: 0.23
Nodes (13): baixar_cidade(), _baixar_overpass(), _consulta_overpass(), consultar_correios(), _distancia_m(), ErroMontagem, _ponto(), Exception (+5 more)

### Community 65 - "Impressoras no Windows"
Cohesion: 0.21
Nodes (13): _classificar_porta(), coletar_impressoras(), _consultar_status_esc_pos(), _consultar_status_esc_pos_tcp(), _executar_powershell(), _executavel_powershell(), imprimir(), Tenta abrir de verdade um socket TCP em `host:porta` — diferente de… (+5 more)

### Community 66 - "Contagem do Caixa"
Cohesion: 0.22
Nodes (13): Grava `dados` de forma atômica (temporário + os.replace). `compacto` é para…, salvar_json(), aplicar_remoto(), _caminho_arquivo(), carregar(), obter_dia(), Contagem manual de caixa por forma de pagamento (Cartão, Dinheiro, Pix), usada…, `{dataIso: {cartao, dinheiro, pix, idEvento}}` de todos os dias já contados… (+5 more)

### Community 67 - "Controller de Clientes"
Cohesion: 0.21
Nodes (6): ClientesController, pyqtSlot, QObject, O cadastro só funciona com a máquina numa rede (ver o topo)., O cliente deste telefone ({"telefone", "nome", "rua", "numero", "bairro",…, Cria ou sobrescreve o cliente com os dados da comanda de Entrega (cliente,…

### Community 68 - "Dev Watch"
Cohesion: 0.24
Nodes (11): _arquivos_observados(), _encerrar_processo(), _esperar_workspace_da_janela(), _iniciar_processo(), main(), _mover_janela_para_workspace(), Roda main.py num subprocesso e reinicia automaticamente sempre que um arquivo…, Consulta o Hyprland pela janela do processo com esse pid e devolve o id do… (+3 more)

### Community 69 - "Testes de Pareamento"
Cohesion: 0.21
Nodes (10): ao_mudar_pareamento(), ao_pedido_de_entrada(), log(), Verifica o pareamento (entrada aprovada na rede) e o cadastro de clientes…, tick(), _argumentos_do_cadastro(), Verifica manualmente a sincronização do cadastro de usuários entre "máquinas" —…, Nome e código depois de --cadastrar, com padrão para quem esquecer. (+2 more)

### Community 70 - "Localização da Pizzaria"
Cohesion: 0.22
Nodes (12): math, _cidade_da_pizzaria(), A cidade da localização definida na tela Rede, para o Maps não achar a rua…, bbox(), _caminho_arquivo(), carregar(), _limite_entrega(), normalizar_registro() (+4 more)

### Community 71 - "Rede do QML"
Cohesion: 0.18
Nodes (9): pyqt6, pyqt6_qtqml, QNetworkAccessManager, QQmlNetworkAccessManagerFactory, FabricaRedeQml, _GerenciadorComUserAgent, instalar(), User-Agent nos pedidos de rede feitos pelo QML. O engine QML baixa imagens… (+1 more)

### Community 72 - "Normalização de Ruas"
Cohesion: 0.24
Nodes (13): normalizar(), Minúsculas e sem acento, que é a forma comparável de tudo aqui. Sem isto,…, adicionar(), chave_rua(), _limpar(), marcar_correios(), preparar(), _normalizar_bairro() (+5 more)

### Community 73 - "Registro Alterações Caixa"
Cohesion: 0.23
Nodes (6): (codigo, cliente, valor) da comanda, lidos do .txt enquanto ele ainda existe.…, Anota que uma comanda JÁ FECHADA foi corrigida, para a linha sair no cupom de…, Anota que uma comanda JÁ FECHADA foi apagada de vez. Chamado por…, Grava e anuncia à malha — o que edição e exclusão têm em comum. O registro…, Anota uma edição ou exclusão de qualquer comanda — com baixa ou sem — para as…, AAAA-MM-DD" do dia da comanda, deduzido do nome do arquivo (que já embute a…

### Community 74 - "Espaçamento de Seções"
Cohesion: 0.18
Nodes (12): categoria_campo(), linhas_espacamento_secoes(), linhas_separador_antes(), Lista de linhas vazias usada como espaçador entre seções da comanda…, Quantas linhas de traço ("-" * 40) entram ANTES de `campo` numa comanda em que…, Categoria de `campo` (ver CATEGORIA_CAMPO) — "" para uma chave desconhecida, o…, linhas_modalidade(), montar_linhas_por_ordem() (+4 more)

### Community 75 - "Quebra e Pintura Linhas"
Cohesion: 0.18
Nodes (12): _desenhar_icone(), _desenhar_separador(), _despejar_palavra(), _largura_celula(), _pintar_linhas(), _quebrar_em_linhas_fisicas(), A largura da célula da grade para um texto de `tamanho_px` de altura. Uma linha…, Põe `palavra` (glifos ainda sem posição) na linha em construção, descendo para… (+4 more)

### Community 76 - "Printer Service"
Cohesion: 0.23
Nodes (6): PrinterService, O caminho de texto, com uma exceção: o título da modalidade sai como imagem,…, O conteúdo sem os marcadores de tamanho exato (ver…, Envia `conteudo` (bytes crus, já formatados em ESC/POS) para a impressora…, Retorna a `InfoImpressora` configurada, ou None se não encontrada. Se…, O conteúdo pronto pra ir ao papel: a comanda desenhada como imagem, quando há…

### Community 77 - "Impressora Windows Bematech"
Cohesion: 0.29
Nodes (10): _configurar_porta_serial(), _executavel_powershell(), garantir_impressora_bematech(), _log(), _logar_resultado(), Automatiza, no Windows, a configuração da impressora térmica Bematech MP-4200…, Configura baud/paridade/bits/controle-de-fluxo da porta COM virtual via `mode`…, Localiza a Bematech MP-4200 TH nas portas USB e garante que existe uma fila de… (+2 more)

### Community 78 - "Controller de Rascunhos"
Cohesion: 0.18
Nodes (7): pyqtSlot, Descarta o rascunho — pelo × do card, ou porque ele virou comanda (ver…, Soma o valor dos itens do rascunho. Mesma conta de…, Um resumo por rascunho, do mais recente para o mais antigo — só o que o card da…, O rascunho inteiro, pronto para repovoar o formulário. {} quando ele não existe…, Grava e devolve o id (novo, se o registro veio sem um). "" quando a gravação…, _valor_total_itens()

### Community 79 - "Lançador Windows"
Cohesion: 0.25
Nodes (10): _avisar(), main(), _pythons_candidatos(), _raiz_do_projeto(), Lançador do sistema para Windows — é isto que vira o .exe de duplo clique. Não…, Pasta onde está o main.py. Procura ao lado do executável e nos diretórios acima…, Interpretadores a tentar, do mais específico para o mais genérico. O venv do…, Mostra o erro numa caixa do Windows; no resto, imprime. Sem isto, um .exe… (+2 more)

### Community 80 - "Montagem de Extras JS"
Cohesion: 0.27
Nodes (7): adicionaisDaLinha(), bordaDaLinha(), _comoObjeto(), formatarMoeda(), gravarNaLinha(), valorAjustado(), valorNum()

### Community 81 - "Fontes de Impressão"
Cohesion: 0.18
Nodes (11): _comando_tamanho_fonte(), _comando_tamanho_px(), fonte_impressao(), formatar_com_atributos(), limitar_tamanho_fonte(), _multiplicador_fonte(), O tamanho em pixels dentro da faixa aceita, ou a base quando o valor não é um…, Converte um tamanho em pixels no multiplicador ESC/POS mais próximo (1 a 8).… (+3 more)

### Community 82 - "Tabelas de Texto"
Cohesion: 0.22
Nodes (10): _acomodar_tamanho(), formatar_tabela(), largura_visivel(), _linhas_do_nome(), quebrar_linha(), Decide se o "(BROTO)" cabe na linha do item ou tem de descer para a linha de…, A coluna do item em uma ou mais linhas: a primeira alinhada com o valor, as…, Alinha pedido e valor em uma coluna "|" e separa cada grupo com uma linha em… (+2 more)

### Community 83 - "Barramento de Eventos"
Cohesion: 0.24
Nodes (5): BarramentoEventos, `enviar_para_peers(evento, socket_excluido)` é injetado por quem monta este…, `callback(payload)` roda toda vez que um evento `tipo_evento` chega de outra…, Anuncia um evento novo, desta máquina, pra malha inteira. Não chama os…, Chamado por RedeService quando uma mensagem `{"tipo": "evento", ...}` chega de…

### Community 84 - "Provedor de Ícones"
Cohesion: 0.20
Nodes (7): collections, pyqt6_qtquick, QQuickImageProvider, qtawesome, IconProvider, Expõe os ícones do pacote `qtawesome` (Font Awesome, Material Design Icons…, urllib_parse

### Community 85 - "Destino do Pedido JS"
Cohesion: 0.24
Nodes (3): acrescentarAoModelo(), _comoLinha(), inserirEmModelo()

### Community 86 - "Estado de Estilo"
Cohesion: 0.20
Nodes (7): _Estilo, _linhas_com_estilo(), Estado de estilo corrente durante a varredura de uma linha. Vive numa classe, e…, Liga/desliga o atributo que `comando` controla., Quebra uma linha do cupom em [(texto, negrito, sublinhado, reverso,…, O cupom inteiro como lista de linhas, cada uma já quebrada em trechos…, _trechos_da_linha()

### Community 87 - "Grafo e Caminhos"
Cohesion: 0.22
Nodes (4): Grafo, (vértice, distância em metros) do vértice mais próximo do ponto, ou (None,…, (segundos, metros, [vértices]) do caminho mais rápido de origem até destino, ou…, [lat, lon, lat, lon, ...] dos vértices: o traçado que o QML desenha.

### Community 88 - "Busca de Ruas"
Cohesion: 0.22
Nodes (10): buscar_bairros(), buscar_ruas(), _montar_busca(), _para_sugestao(), _preparar_busca(), As listas ordenadas que a busca binária percorre, e os bairros conhecidos com a…, Ruas cujo nome tem uma palavra começando por `termo` — [{"nome", "bairros",…, A rua do índice que é a mesma de `nome` — sem caixa, acento e pontuação, e com… (+2 more)

### Community 89 - "Recibo de Extra"
Cohesion: 0.22
Nodes (4): FGTS.................... R$ 8,00" ocupando a linha inteira, com o valor…, ("23:26", "01/06/2026") a partir do "dd/mm/aaaa HH:MM:SS" gravado no lançamento…, Monta o recibo de pagamento de diária em bytes ESC/POS, pronto pra impressora,…, Pede a impressão do recibo pela malha local, igual a reimprimirComanda — o…

### Community 90 - "Limpeza Servidor Antigo"
Cohesion: 0.33
Nodes (8): _caminho_pid(), _eh_o_servidor(), executar(), _nome_do_processo(), _pasta_base(), Uma vez por abertura: encerra o ppgs_server que a versão anterior do sistema…, A mesma pasta que services/servidor/preparo.py usava., signal

### Community 91 - "Cache de Fechamento"
Cohesion: 0.33
Nodes (8): _caminho_arquivo(), carregar(), listar_dias(), _pasta_fechamentos(), Persistência do resumo de fechamento de caixa — um JSON por dia, na pasta de…, Resumo já salvo para `data_iso` ("AAAA-MM-DD"), ou None se esse dia nunca foi…, Datas ("AAAA-MM-DD") de todo dia já calculado/cacheado nesta máquina — usado…, salvar()

### Community 92 - "Itens de Produção"
Cohesion: 0.29
Nodes (8): _linhas_itens_producao(), Tabela de itens da comanda do pizzaiolo — mesma montagem de grupos de…, formatar_campo(), _montar_linha_exemplo(), Uma linha da comanda de exemplo, a partir dos trechos que a tela mandou (ver…, Envolve `texto` com os comandos ESC/POS ligados/desligados conforme a…, formatar_coluna_pedido(), A coluna do item já estilizada, com o TAMANHO da pizza ("(GRANDE)") no campo…

### Community 93 - "Conexão com Peers"
Cohesion: 0.25
Nodes (4): QHostAddress, Uma instância apareceu na rede (ver services/rede/descoberta.py). A descoberta…, Tenta de novo todo peer que a descoberta já anunciou mas com quem não há…, Abre uma conexão para CADA endereço anunciado pelo peer. Dois lados podem…

### Community 94 - "Resumo de Extras JS"
Cohesion: 0.54
Nodes (7): comoObjeto(), extrasDoItem(), extrasDoSabor(), linhaBorda(), linhasDoItem(), saboresDe(), textoAdicional()

### Community 95 - "Capitalização de Texto JS"
Cohesion: 0.43
Nodes (6): capitalizarCampo(), capitalizarCampoFrase(), capitalizarFrase(), capitalizarNomes(), _maiusculaSegura(), _minusculaSegura()

### Community 96 - "Busca de Comandas JS"
Cohesion: 0.43
Nodes (7): _achatar(), construirIndice(), _faixaPorPrefixo(), _limiteInferior(), _marcarPrefixo(), _ordenadoPor(), ordenar()

### Community 97 - "Montagem de Item JS"
Cohesion: 0.46
Nodes (6): formatarMoeda(), montarAcai(), montarLanche(), montarPizza(), montarSimples(), _somaAdicionais()

### Community 98 - "Formatação JS"
Cohesion: 0.43
Nodes (4): formatar(), moeda(), moedaCurta(), numero()

### Community 99 - "Endereço do QR"
Cohesion: 0.33
Nodes (7): Aceita tanto os bytes crus do arquivo quanto o texto já decodificado — quem…, _texto_limpo(), endereco_da_comanda(), O endereço para o QR. Comanda com endereço validado traz a linha interna com o…, extrair_endereco_qr(), limpar_codigos_impressora(), O endereço completo da linha interna do QR, ou "" quando a comanda não a tem.…

### Community 100 - "Faixa de Números CEP"
Cohesion: 0.29
Nodes (7): faixa_de_numeros(), _fim_do_par(), A UF do estabelecimento. O campo "uf" vem do índice de ruas, que nem sempre já…, Onde termina "766/767" (o lado par e o ímpar da mesma altura): no 767. O ViaCEP…, (início, fim, lado) dos números que um CEP de rua atende, lido do "complemento"…, _sem_acento(), uf_da_localizacao()

### Community 101 - "Comandas Abertas do Dia"
Cohesion: 0.33
Nodes (3): Comandas de `data_iso` que ainda não receberam baixa, inteiras (com o cupom em…, As comandas de Entrega de `data_iso` ainda sem baixa, da mais recente pra mais…, Nomes de arquivo cuja data embutida bate com `data_iso`, sem abrir/ler o…

### Community 102 - "Status de Inicialização"
Cohesion: 0.33
Nodes (3): QObject, Exposto ao QML como `statusController`., StatusInicializacaoService

### Community 108 - "Estilo Reconciliação"
Cohesion: 0.40
Nodes (4): _obter_estilo_reconciliacao(), _payload_estilo(), `_config` já é um dict serializável em JSON (campos/espaçamentos/ idEvento) —…, _resumo_estilo()

### Community 110 - "Paleta e Fontes"
Cohesion: 0.50
Nodes (4): Food Color Palette Reference, Paleta Forno Design System, Caprasimo Font License, Figtree Font License

## Knowledge Gaps
- **8 isolated node(s):** `pizzeria-system`, `P2P Architecture Documentation`, `Paleta Forno Design Document`, `Oven Control Interface`, `Food Color Palette Reference` (+3 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 932 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **17 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `protegido()` connect `Proteção de Slots QML` to `Sugestões de Endereço`, `Serviço de Cardápio`, `Consulta de Comandas`, `Controller de Usuários`, `Controller do Salão`, `Controllers Auxiliares`, `Controller Validação Endereço`, `Estilo da Comanda`, `Imports Stdlib Rede`, `Ações do Fechamento`, `Estatísticas Diárias`, `Pareamento de Máquinas`, `Configuração de Log`, `Impressora Principal da Malha`, `Controllers e Numeração`, `Recibo Fechamento Caixa`, `Controller de Entrega`, `Controller do Balcão`, `Ativação da Malha`, `Controller de Clientes`, `Registro Alterações Caixa`, `Controller de Rascunhos`, `Recibo de Extra`, `Comandas Abertas do Dia`, `Pedido Remoto Consulta`?**
  _High betweenness centrality (0.218) - this node is a cross-community bridge._
- **Why does `RedeService` connect `Malha P2P Gossip` to `Impressora Principal da Malha`, `Propriedades da Rede`, `Printer Service`, `Impressão Remota`, `Barramento de Eventos`, `Conexão com Peers`, `Ativação da Malha`, `Imports Stdlib Rede`, `Anti-entropia e Eleição`, `Pareamento de Máquinas`?**
  _High betweenness centrality (0.097) - this node is a cross-community bridge._
- **Why does `FechamentoController` connect `Fechamento Sync Remoto` to `Recibo de Extra`, `Comandas Abertas do Dia`, `Baixa Remota`, `Edição de Caixa Remota`, `Extra Apagado Remoto`, `Registro Alterações Caixa`, `Recibo Fechamento Caixa`, `Controllers Auxiliares`, `Imports Stdlib Rede`, `Ações do Fechamento`, `Reconciliação Caixa Remoto`?**
  _High betweenness centrality (0.092) - this node is a cross-community bridge._
- **Are the 2 inferred relationships involving `RedeService` (e.g. with `PrinterService` and `BarramentoEventos`) actually correct?**
  _`RedeService` has 2 INFERRED edges - model-reasoned connections that need verification._
- **What connects `pizzeria-system`, `P2P Architecture Documentation`, `Paleta Forno Design Document` to the rest of the system?**
  _8 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Sugestões de Endereço` be split into smaller, more focused modules?**
  _Cohesion score 0.0505175983436853 - nodes in this community are weakly interconnected._
- **Should `Criptografia da Rede` be split into smaller, more focused modules?**
  _Cohesion score 0.060655737704918035 - nodes in this community are weakly interconnected._