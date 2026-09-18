# Graph Report - pizzeria_system  (2026-09-18)

## Corpus Check
- 115 files · ~169,035 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 99 file(s) not represented in the graph (top: .qml 87, (none) 6, .ttf 5)

## Summary
- 2288 nodes · 4637 edges · 113 communities (105 shown, 8 thin omitted)
- Extraction: 99% EXTRACTED · 1% INFERRED · 0% AMBIGUOUS · INFERRED: 38 edges (avg confidence: 0.87)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `bd8a36d0`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- SugestoesEnderecoService
- seguranca.py
- cardapioService.py
- atualizador.py
- ConsultaController
- UsuariosController
- indicePedidos.py
- cnefe.py
- SalaoController
- cofreLocal.py
- validacaoEndereco.py
- RedeService
- buscaCardapio.py
- comandaParserService.py
- indiceRuas.py
- historicoEnderecos.py
- Descoberta
- sugestoesEndereco.py
- FechamentoController
- ValidacaoEnderecoController
- ComandaEstiloController
- comandaEstiloService.py
- comandaImagemService.py
- redeService.py
- sys
- protegido
- EstatisticasController
- ._processar_mensagem
- senhaDono.py
- QTcpSocket
- linux.py
- historicoEventos.py
- grafoRuas.py
- _desenhar_modelo_rascunho
- usuarios.py
- logConfig.py
- pyqtSlot
- requisicaoHttp.py
- preConfig.py
- pyqtProperty
- os
- RotasController
- windows.py
- estatisticasService.py
- ._calcular_resumo_dia
- rascunhosPedido.py
- tombstones.py
- configurar_impressora_bematech.py
- alteracoesComandas.py
- sequenciaComandas.py
- diagnosticar_impressora.py
- _bloco_tabela_rascunho
- comandaTextoService.py
- edicoesCaixa.py
- relogio.py
- EntregaController
- despesasCaixa.py
- extrasCaixa.py
- PrinterService
- _carregado
- caminhos.py
- .criarRede
- splashInicializacao.py
- _aplicar_estilo_remoto
- montadorIndiceRuas.py
- enviar_para_impressora
- contagemCaixa.py
- ClientesController
- dev_watch.py
- pareamento_teste.py
- ._listar_mesas_locais
- redeQml.py
- normalizar
- .registrarEdicaoCaixa
- montar_linhas_por_ordem
- titulo_em_raster
- graphify
- impressoraWindows.py
- .listarRascunhos
- subprocess
- MontagemExtras.js
- formatar_com_atributos
- quebrar_linha
- BarramentoEventos
- iconProvider.py
- DestinoPedido.js
- _linhas_com_estilo
- mesma_rua
- rua_equivalente
- ._montar_recibo_extra
- limpezaServidorAntigo.py
- fechamentoCache.py
- formatar_campo
- ._tentar_conectar_a_peer
- ResumoExtras.js
- Texto.js
- BuscaComandas.js
- MontagemItem.js
- Formato.js
- _itens_pendentes_cozinha
- faixa_de_numeros
- _mesclar_ajustes
- StatusInicializacaoService
- _iniciar_rede
- RoteiroLancamento.js
- ._imprimir_localmente_e_notificar
- Paleta Forno Design System
- .imprimirComandaExemplo
- Docker Compose Mesh Test
- pizzeria-system

## God Nodes (most connected - your core abstractions)
1. `protegido()` - 131 edges
2. `RedeService` - 105 edges
3. `FechamentoController` - 81 edges
4. `SugestoesEnderecoService` - 40 edges
5. `ConsultaController` - 34 edges
6. `normalizar()` - 33 edges
7. `UsuariosController` - 32 edges
8. `normalizar_endereco()` - 27 edges
9. `ComandaEstiloController` - 26 edges
10. `SalaoController` - 25 edges

## Surprising Connections (you probably didn't know these)
- `Como o projeto funciona` --references--> `BalcaoController`  [INFERRED]
  README.md → controllers/balcaoController.py
- `Como o projeto funciona` --references--> `ConsultaController`  [INFERRED]
  README.md → controllers/consultaController.py
- `Como o projeto funciona` --references--> `EntregaController`  [INFERRED]
  README.md → controllers/entregaController.py
- `Paleta Forno Design System` --semantically_similar_to--> `Food Color Palette Reference`  [INFERRED] [semantically similar]
  design/Paleta Forno.html → design/Food-Color-Palette-6-768x768.webp
- `_payload_teste_raster()` --calls--> `para_raster()`  [EXTRACTED]
  Config/diagnosticar_impressora.py → services/comandaImagemService.py

## Import Cycles
- 3-file cycle: `services/comandaEstiloService.py -> services/comandaImagemService.py -> services/comandaParserService.py -> services/comandaEstiloService.py`

## Hyperedges (group relationships)
- **Design System Foundations** — design_paleta_forno, qml_estilo_fontes_caprasimo, qml_estilo_fontes_figtree, design_food_color_palette [INFERRED 0.85]

## Communities (113 total, 8 thin omitted)

### Community 0 - "SugestoesEnderecoService"
Cohesion: 0.05
Nodes (29): _bairros_do_photon(), _features_de(), pyqtProperty, pyqtSlot, QObject, [(properties, coordinates)] do GeoJSON do Photon, ou None se a resposta não…, Ruas salvas nesta máquina (histórico e índice) que casam com `termo` —…, Mesmo papel de sugerirEnderecosLocais, para o campo Bairro. (+21 more)

### Community 1 - "seguranca.py"
Cohesion: 0.06
Nodes (34): cryptography_hazmat_primitives, cryptography_hazmat_primitives_asymmetric_x25519, cryptography_hazmat_primitives_ciphers_aead, cryptography_hazmat_primitives_kdf_hkdf, _caminho_chave(), carregar_chave(), chave_indice_clientes(), _derivar() (+26 more)

### Community 2 - "cardapioService.py"
Cohesion: 0.06
Nodes (41): resumo(), tick(), _caminho_arquivo(), _caminho_versoes(), CardapioController, carregar(), _carregar_versoes(), _categoria() (+33 more)

### Community 3 - "atualizador.py"
Cohesion: 0.06
Nodes (52): _arquivos_cardapio_modificados_localmente(), _atualizar(), _branch_atual(), _caminho_relativo_cardapio(), checar_atualizacoes(), _commits_atras(), _desfazer_guarda_cardapio_local(), _eh_repositorio_git() (+44 more)

### Community 4 - "ConsultaController"
Cohesion: 0.06
Nodes (27): ConsultaController, pyqtSlot, QObject, Descarta os conflitos que a regra antiga gravou sem olhar conteúdo. Até aqui…, A "versão" de cada comanda é o id de linha do tempo dela MAIS a impressão…, Decide se vale puxar do peer a comanda `nome_arquivo`. Só o transporte decide…, A data mais antiga (como "AAAAMMDD") que ainda conta como recente. Mesma…, 20260731" -> "31/07/2026", o mesmo formato do cabeçalho do cupom (e o que… (+19 more)

### Community 5 - "UsuariosController"
Cohesion: 0.06
Nodes (23): pyqtSlot, QObject, Sem janela temporal, ao contrário de "extras"/"fechamento": um cadastro não é…, Reação ao gossip "usuario_alterado" — para um cadastro novo OU uma correção…, Grava um usuário aprendido de fora, venha ele do gossip ou da reconciliação —…, Todos os usuários, ordenados por nome, cada um com "duplicado": True quando…, Tudo que se sabe sobre uma pessoa do cadastro, para o popup que abre ao clicar…, Se as ações protegidas (imprimir, lançar, editar comanda fechada, apagar… (+15 more)

### Community 6 - "indicePedidos.py"
Cohesion: 0.08
Nodes (43): contextlib, _calcular_impressao(), _caminho_conflitos(), _caminho_eventos(), _carregar(), carregar_conflitos(), carregar_indice(), _carregar_para_gravar() (+35 more)

### Community 7 - "cnefe.py"
Cohesion: 0.11
Nodes (28): csv, io, baixar_e_montar(), codigo_municipio(), _descartar_cache(), disponivel_para(), ErroCnefe, _float() (+20 more)

### Community 8 - "SalaoController"
Cohesion: 0.18
Nodes (10): pyqtSlot, QObject, Gerencia comandas de mesa (Salao.qml): diferente de Balcão/Entrega, uma comanda…, Cria (id vazio) ou atualiza uma mesa aberta. Recusa salvar se OUTRA mesa já…, Cancela uma mesa aberta sem imprimir nada (mesa aberta por engano, por exemplo)…, Itens da mesa que ainda não foram impressos para o pizzaiolo — o que Salao.qml…, Imprime a via de produção (a que vai pro pizzaiolo) com os itens ainda não…, Fecha a conta: monta o cupom final (itens + divisão da conta já resolvida —… (+2 more)

### Community 9 - "cofreLocal.py"
Cohesion: 0.10
Nodes (41): _caminho_arquivo(), _caminho_marca(), _caminho_windows(), _chave_linux(), _chave_windows(), cifrar(), decifrar(), _decodificar() (+33 more)

### Community 10 - "validacaoEndereco.py"
Cohesion: 0.13
Nodes (34): cep_da_rua(), cep_digitos(), _cep_util(), _fechar(), _float(), formatar_cep(), interpretar(), limite_entrega() (+26 more)

### Community 11 - "RedeService"
Cohesion: 0.06
Nodes (15): QObject, Aprende reservas de número feitas em outra máquina. É este caminho — não a…, Quando um peer NOVO entra na malha (a quantidade aumentou, não só mudou),…, Anuncia `payload` (precisa ser serializável em JSON) pra malha inteira sob o…, Registra `callback(payload)` pra rodar sempre que um evento `tipo_evento`…, Inscreve um domínio de estado (pedidos, mesas, cardápio, fechamento...) na…, Anuncia um hash por dia, só dos dias dentro da janela de retenção. A janela…, As fontes da máquina que a malha está usando pra imprimir agora, pra alimentar… (+7 more)

### Community 12 - "buscaCardapio.py"
Cohesion: 0.08
Nodes (38): bisect, analisar_item_comanda(), _aplicar_promocao(), aquecer(), _arquivo_promocao_do_dia(), _assinatura_dos_arquivos(), buscar(), _carregar_promocoes() (+30 more)

### Community 13 - "comandaParserService.py"
Cohesion: 0.07
Nodes (38): campos_comparaveis(), comparar(), diferencas_entre(), _formatar(), Compara duas versões da MESMA comanda campo a campo, para dizer se elas são de…, Lista vira uma linha por elemento; o resto vira texto puro. É o que a tela…, Os campos cujo valor difere entre as duas versões, na ordem de ROTULOS (a mesma…, Atalho para os dois passos acima, que é como quem chama sempre usa. (+30 more)

### Community 14 - "indiceRuas.py"
Cohesion: 0.11
Nodes (36): aplicar_montagem(), aplicar_remoto(), base(), bloco_da_chave(), _caminho_arquivo(), _carregar(), chave_rua(), chaves_consultadas() (+28 more)

### Community 15 - "historicoEnderecos.py"
Cohesion: 0.12
Nodes (33): O termo digitado normalizado e, quando fica diferente, também com a abreviação…, termos_de_busca(), aplicar_remoto(), aprendido(), buscar_bairros(), buscar_ruas(), _caminho_arquivo(), carregar() (+25 more)

### Community 16 - "Descoberta"
Cohesion: 0.09
Nodes (10): Descoberta, DescobertaBroadcast, DescobertaZeroconf, QObject, Interface comum das estratégias de descoberta. Emite `peerDescoberto` para cada…, Começa a anunciar esta instância e a procurar as outras. `porta_tcp` é a porta…, A máquina entrou numa rede: o anúncio passa a dizer isso, para as pareadas…, Descoberta por mDNS/DNS-SD: anuncia esta instância como um serviço `_pizzaria-… (+2 more)

### Community 17 - "sugestoesEndereco.py"
Cohesion: 0.12
Nodes (27): concurrent_futures, Validação do endereço de entrega (qml/components/DeliveryAddressValidator.qml).…, bairros_equivalentes(), escolher_bairro(), formatar_endereco(), normalizar_endereco(), palavras_distintivas(), Comparação de endereços e grafia formatada: reconhece que o endereço salvo… (+19 more)

### Community 18 - "FechamentoController"
Cohesion: 0.04
Nodes (20): FechamentoController, QObject, Fechamento de caixa diário: soma o valor das comandas **fechadas**…, Reação a um "fechamento_atualizado" vindo de OUTRA máquina. A mensagem é…, Payload deliberadamente vazio de números: quem recebe recalcula o dia com as…, Anuncia as baixas recentes. A janela recorta só o que é ANUNCIADO: o arquivo em…, Só puxa o que não existe aqui. O comparador padrão de…, Reação ao gossip "comanda_baixada" — o caminho rápido, pra baixa dada em outra… (+12 more)

### Community 19 - "ValidacaoEnderecoController"
Cohesion: 0.10
Nodes (15): pyqtSlot, QObject, A sugestão da casa `numero` da `rua`: a da última comanda para ela, senão a do…, {rua, numero, bairro, pistaCondominio} do texto livre: o Enter sem escolher…, Síncrono, a cada tecla: histórico e índice de ruas desta máquina., Locais + Photon, numa thread. Responde por sugestoesProntas., Valida a sugestão escolhida com o número do campo. Responde por validacaoPronta…, Mesma validação, partindo do CEP digitado pelo atendente. (+7 more)

### Community 20 - "ComandaEstiloController"
Cohesion: 0.13
Nodes (10): ComandaEstiloController, pyqtSlot, QObject, Ponte pra tela de Configurações (QML) ler/gravar o estilo acima., Catálogo pro seletor de fonte da comanda: a opção padrão (imprimir em texto,…, Catálogo pro seletor de modelo de desenho (ver MODELOS_IMPRESSAO). Ao contrário…, Se ESTA máquina tem a família `familia` instalada. Diferente de listarFontes,…, De qual máquina veio a lista de listarFontes(), pra tela poder dizer isso em… (+2 more)

### Community 21 - "comandaEstiloService.py"
Cohesion: 0.12
Nodes (22): atributos_campo(), _atributos_campo_padrao(), _caminho_arquivo(), _carregar(), _herdar_estilo_do_nome_do_item(), linha_endereco_qr(), linhas_espacamento_corte(), modelo_impressao() (+14 more)

### Community 22 - "comandaImagemService.py"
Cohesion: 0.10
Nodes (29): aquecer_familias(), aquecer_icones_pagamento(), _cidade_da_pizzaria(), _comandos_raster(), _desenhar_icone(), desenhar_qr_endereco(), _empacotar(), endereco_da_comanda() (+21 more)

### Community 23 - "redeService.py"
Cohesion: 0.10
Nodes (23): base64, hashlib, json, pyqt6_qtnetwork, random, criar_descoberta(), enderecos_para_anunciar(), _ip_por_rota() (+15 more)

### Community 24 - "sys"
Cohesion: 0.09
Nodes (15): Registra as fontes embarcadas do app e define a Figtree como fonte padrão. Por…, Verifica manualmente a sincronização do cardápio entre "máquinas", em especial…, Verifica manualmente a sincronização de Config/estilo_impressao.json entre…, Simula alguém tirando um pedido no Balcão desta "máquina" (container), usando o…, Verifica manualmente o histórico de eventos da malha…, Mostra quais outras "máquinas" (containers) esta instância enxerga na malha…, Fica rodando e imprimindo a letra desta "máquina" a cada 3s — usado só…, Verifica manualmente a sincronização da ORDEM dos campos da comanda… (+7 more)

### Community 25 - "protegido"
Cohesion: 0.09
Nodes (19): protegido(), decorar(), Decorador para os métodos expostos à QML (os @pyqtSlot dos controllers):…, _hoje_iso(), pyqtSlot, Se o resumo em cache foi gravado por uma versão do app que já montava tudo que…, Imprime o cupom-resumo do dia (ver _montar_recibo_fechamento). Chamado só pelo…, As comandas de Entrega de `data_iso` ainda sem baixa, da mais recente pra mais… (+11 more)

### Community 26 - "EstatisticasController"
Cohesion: 0.12
Nodes (13): EstatisticasController, trabalho(), _hoje_iso(), pyqtSlot, QObject, As alterações do dia. As correções de caixa gravadas antes de…, Monta e grava `data_iso`. Devolve as estatísticas gravadas., Chamado pelo "Fechar Caixa": grava o dia e avisa as outras máquinas. (+5 more)

### Community 27 - "._processar_mensagem"
Cohesion: 0.09
Nodes (8): Ponte entre BarramentoEventos e os sockets reais: manda `evento` pra todo peer…, Um ciclo de anti-entropy: monta o resumo atual de cada domínio registrado e…, Compara o resumo recebido de um peer com o estado local de cada domínio: aplica…, Se `id_maquina` ainda é uma candidata legítima agora (continua conectada — ou é…, Converte um nome de máquina (estável — ver _nome_maquina_fixada) no id_maquina…, Eleição "sticky com prioridade": entre máquinas do mesmo nível de prioridade,…, Chamado ao processar o handshake "identificar" de um peer que acabou de…, Reação a um "impressora_fixada" publicado por OUTRA máquina — replica o mesmo…

### Community 28 - "senhaDono.py"
Cohesion: 0.12
Nodes (24): hmac, secrets, aplicar_remoto(), _bytes_da_senha(), _caminho_arquivo(), carregar(), conferir(), definida() (+16 more)

### Community 29 - "QTcpSocket"
Cohesion: 0.16
Nodes (9): QTcpSocket, Um socket de pareamento fechou (ou foi fechado). Do lado que aprova, o pedido…, Devolve False quando o socket foi recusado e não se deve continuar lendo os…, Lado que PEDE: abre o pareamento com a máquina escolhida, por todos os…, Fecha e registra. O registro é o ponto: uma máquina recusada (hoje, na prática,…, Um socket que nunca chegou a conectar não emite `disconnected`, então…, Primeiro frame de uma conexão de entrada. Devolve False quando o socket foi…, Lado que APROVA: uma máquina sem chave pediu para entrar. (+1 more)

### Community 30 - "linux.py"
Cohesion: 0.14
Nodes (24): _classificar_porta(), coletar_impressoras(), _descricao_e_status(), _destino_padrao(), _dispositivos_conectados_agora(), _dispositivos_por_impressora(), _executar(), _extrair_porta() (+16 more)

### Community 31 - "historicoEventos.py"
Cohesion: 0.14
Nodes (22): tick(), aplicar(), _caminho(), _carregar(), contar_autorizacoes(), _detalhe_de(), listar(), obter() (+14 more)

### Community 32 - "grafoRuas.py"
Cohesion: 0.06
Nodes (35): heapq, math, baixar_elementos(), _caminho_cache(), comparar_entregas(), _consulta_overpass(), _distancia_m(), ErroRota (+27 more)

### Community 33 - "_desenhar_modelo_rascunho"
Cohesion: 0.10
Nodes (24): _desenhar_modelo_classico(), _desenhar_modelo_rascunho(), _desenho_do_modelo(), _espessura_do_traco(), _icones_da_comanda(), _linhas_entre_itens(), _por_linha_fisica(), A comanda com a tabela de itens em três colunas, ou None quando este cupom não… (+16 more)

### Community 34 - "usuarios.py"
Cohesion: 0.15
Nodes (23): apagar(), aplicar_edicao_remota(), _caminho_arquivo(), carregar(), codigo_em_uso(), editar(), existe_algum(), listar() (+15 more)

### Community 35 - "logConfig.py"
Cohesion: 0.11
Nodes (16): caminho_arquivo_log(), configurar_logging(), _EscritaParaLog, _instalar_captura_de_excecoes(), _ao_escapar_excecao(), _ao_escapar_excecao_em_thread(), instalar_captura_de_mensagens_qt(), _raiz_projeto() (+8 more)

### Community 36 - "pyqtSlot"
Cohesion: 0.09
Nodes (11): pyqtSlot, Máquinas que anunciam impressora agora (esta + peers) — as opções disponíveis…, Fixa manualmente `nomeMaquina` como a máquina que imprime pra malha inteira…, Info da impressora que a malha está usando pra imprimir agora (a máquina eleita…, Adota `dados` como a localização da pizzaria e anuncia à malha. Qualquer…, Até quantos minutos de carro a pizzaria entrega (a zona de entrega do validador…, Última decisão vence, pelo relógio lógico: uma localização antiga chegando…, Lado que APROVA: entrega a chave da rede à máquina que pediu. Quem chama já… (+3 more)

### Community 37 - "requisicaoHttp.py"
Cohesion: 0.11
Nodes (19): certifi, gzip, baixar_arquivo(), _corpo(), ErroRequisicao, obter_json(), obter_texto(), Exception (+11 more)

### Community 38 - "preConfig.py"
Cohesion: 0.14
Nodes (21): _comandos_de_instalacao(), _configurar_estilo_qt_quick(), _dependencias_aplicaveis(), _dica_pacote_da_distro(), _em_ambiente_virtual(), _erro_de_import(), garantir_dependencias(), _garantir_modulo() (+13 more)

### Community 39 - "pyqtProperty"
Cohesion: 0.10
Nodes (9): pyqtProperty, Nome da máquina fixada manualmente (ver fixarImpressoraPrincipal), ou "" quando…, {"endereco", "descricao", "cidade", "lat", "lon", "origem", "idEvento"}, ou {}…, Máquinas pareadas que esta enxerga enquanto não tem chave., O pedido de entrada feito por esta máquina: {} ou {"id", "nome", "estado",…, Pedidos de outras máquinas esperando aprovação aqui., Quem guarda a chave local desta máquina (ver cofreLocal.protecao): a tela avisa…, Letra (A, B, C...) desta máquina por ordem de entrada dos PROCESSOS atualmente… (+1 more)

### Community 40 - "os"
Cohesion: 0.13
Nodes (21): Cadastro de clientes da Entrega: busca por telefone (o autofill) e gravação,…, Estatísticas diárias (services/estatisticasService.py) para o "Fechar Caixa" e…, QObject, RascunhosController, Os pedidos começados e não finalizados, para a faixa no topo de Balcão e…, Comparação de rotas de entrega da tela Mapa (qml/pages/mapa/Maps.qml): com a…, Cadastro de usuários e o guarda das ações destrutivas. Duas responsabilidades…, datetime (+13 more)

### Community 41 - "RotasController"
Cohesion: 0.16
Nodes (7): pyqtProperty, pyqtSlot, QObject, Responde por comparacaoPronta (o dict de grafoRuas.comparar_entregas) ou…, Fechamento do sistema: um download em andamento não tenta o próximo servidor., Garante o grafo em memória, do cache ou baixado. Não faz nada se ele já está…, RotasController

### Community 42 - "windows.py"
Cohesion: 0.12
Nodes (24): dataclasses, re, services_printer, coletar_informacoes_impressoras(), Coleta as impressoras instaladas no sistema operacional atual. Detecta…, _imprimir_relatorio(), Diagnóstico das impressoras instaladas no sistema. Rode com: python -m…, eh_bematech_mp4200th() (+16 more)

### Community 43 - "estatisticasService.py"
Cohesion: 0.16
Nodes (19): agregar(), _caminho(), carregar(), _centavos(), data_valida(), datas_do_periodo(), _hora(), listar_dias() (+11 more)

### Community 44 - "._calcular_resumo_dia"
Cohesion: 0.10
Nodes (10): fmt(), {"dinheiro", "pix", "cartao"} com a soma de `comandas` (a lista já filtrada de…, Bloco "ALTERAÇÕES APÓS A BAIXA" do cupom: uma entrada por comanda já fechada…, Monta, em bytes ESC/POS, o cupom-resumo impresso ao clicar "Fechar Caixa":…, Comandas de `data_iso` que ainda não receberam baixa, inteiras (com o cupom em…, Uma comanda qualquer do disco, no mesmo formato de listarComandasAbertas mais o…, Nomes de arquivo cuja data embutida bate com `data_iso`, sem abrir/ler o…, Abre uma comanda do dia e extrai dela os campos de cabeçalho que tanto o resumo… (+2 more)

### Community 45 - "rascunhosPedido.py"
Cohesion: 0.19
Nodes (18): apagar(), _caminho(), _ler(), listar(), _normalizar_id(), obter(), pasta(), purgar_antigos() (+10 more)

### Community 46 - "tombstones.py"
Cohesion: 0.17
Nodes (20): mais_novo(), True se `id_a` é estritamente mais recente que `id_b`. Único ponto de…, _caminho_arquivo(), carregar(), _carregar_tudo(), mesclar(), _migrar_formato_antigo(), _migrar_valor_antigo() (+12 more)

### Community 47 - "configurar_impressora_bematech.py"
Cohesion: 0.27
Nodes (17): aplicar_modo_raw_imediatamente(), configurar_fila_cups(), encontrar_dispositivo_tty(), encontrar_stty(), enviar_teste(), executar(), exigir_root(), garantir_cups_instalado() (+9 more)

### Community 48 - "alteracoesComandas.py"
Cohesion: 0.21
Nodes (15): aplicar(), _caminho_arquivo(), carregar(), dias_com_alteracoes(), listar_do_dia(), obter(), Registro persistido de TODA edição e exclusão de comanda — com baixa ou sem —…, Grava uma alteração aprendida de outra máquina. Devolve o dia atingido quando… (+7 more)

### Community 49 - "sequenciaComandas.py"
Cohesion: 0.18
Nodes (17): _caminho_arquivo(), carregar(), dia(), dias_recentes(), _maior_numero(), mesclar_dia(), purgar_antigos(), Registro das reservas de número de comanda do dia — o que faz os dois últimos… (+9 more)

### Community 50 - "diagnosticar_impressora.py"
Cohesion: 0.18
Nodes (16): argparse, config, _executavel_powershell(), listar_impressoras(), log(), main(), _payload_teste(), _payload_teste_raster() (+8 more)

### Community 51 - "_bloco_tabela_rascunho"
Cohesion: 0.12
Nodes (13): _bloco_tabela_rascunho(), _Celula, _colunas_rascunho(), _largura_da_coluna_valor(), Um pedaço de texto a desenhar num retângulo: o texto, a fonte dele e onde ele…, A altura que este texto ocupa na coluna, decidindo de passagem como ele vai…, (x, largura) de cada uma das três colunas, em dots, dada a largura já medida da…, + BACON (R$ 5,00)", e com o sabor no fim quando a pizza tem mais de um — senão,… (+5 more)

### Community 52 - "comandaTextoService.py"
Cohesion: 0.18
Nodes (16): _como_lista_de_dicts(), dividir_sabores(), _extras_adicionais(), _formatar_borda(), item_preenchido(), _linhas_de_list_model(), montar_grupos(), Montagem do texto de comandas (tabela de itens, valores) compartilhada por… (+8 more)

### Community 53 - "edicoesCaixa.py"
Cohesion: 0.19
Nodes (16): aplicar(), _caminho_arquivo(), carregar(), contar_do_usuario(), listar_do_dia(), obter(), Registro persistido das ALTERAÇÕES feitas em comandas que já receberam baixa —…, Grava uma alteração e devolve o id do registro. `quando` vem preenchido quando… (+8 more)

### Community 54 - "relogio.py"
Cohesion: 0.20
Nodes (14): _analisar(), _formatar(), id_para_instante(), instante_do_id(), _maquina_local(), _microssegundos_agora(), novo_id(), observar() (+6 more)

### Community 55 - "EntregaController"
Cohesion: 0.08
Nodes (22): P2P Architecture Documentation, _endereco_para_qr(), EntregaController, pyqtSlot, QObject, Nome do .txt gravado pela última chamada bem-sucedida de…, Gera o arquivo .txt do pedido de entrega e pede a impressão pela malha local…, Igual a enviarPedido, mas nunca tenta imprimir — usado pelo botão 'Lançar', que… (+14 more)

### Community 56 - "despesasCaixa.py"
Cohesion: 0.22
Nodes (15): apagar(), aplicar_edicao_remota(), _caminho_arquivo(), carregar(), editar(), listar_do_dia(), Registro persistido das DESPESAS do dia — dinheiro que sai do caixa para pagar…, Apaga um lançamento — tombstone genérico de services/rede/tombstones.py… (+7 more)

### Community 57 - "extrasCaixa.py"
Cohesion: 0.22
Nodes (15): apagar(), aplicar_edicao_remota(), _caminho_arquivo(), carregar(), editar(), listar_do_dia(), Registro persistido dos pagamentos de diária a funcionários — dinheiro que sai…, Apaga um lançamento — tombstone genérico de services/rede/tombstones.py… (+7 more)

### Community 58 - "PrinterService"
Cohesion: 0.10
Nodes (14): BalcaoController, pyqtSlot, QObject, Nome do .txt gravado pela última chamada bem-sucedida de…, Gera o arquivo .txt do pedido e pede a impressão pela malha local `copias`…, Igual a enviarPedido, mas nunca tenta imprimir — usado pelo botão 'Lançar', que…, Dispara em segundo plano a busca pela impressora que esta máquina usaria para…, Monta o texto da comanda, grava o .txt e propaga para a rede local. Não imprime… (+6 more)

### Community 59 - "_carregado"
Cohesion: 0.16
Nodes (17): bairros_da_rua(), buscar_ruas(), caminho_banco(), _carregado(), casa(), _casa_termo(), _conectar(), endereco() (+9 more)

### Community 60 - "caminhos.py"
Cohesion: 0.13
Nodes (22): _caminho_arquivo(), carregar(), esta_fechada(), mesclar(), purgar_apagadas(), Registro persistido das comandas que já receberam baixa — o que separa "a…, Descarta as baixas de comandas que foram apagadas de propósito — é daí que vem…, `{nome_arquivo: idEvento}` de todas as comandas com baixa, do ponto de vista… (+14 more)

### Community 61 - ".criarRede"
Cohesion: 0.14
Nodes (5): Força uma nova checagem da impressora local agora, em vez de esperar o próximo…, Primeira máquina: gera a chave e passa a ser a rede. Devolve "" ou o motivo de…, Abre os sockets e começa a anunciar/descobrir peers. Precisa ser chamado depois…, Liga o que só existe entre máquinas pareadas: discar para os peers, refazer…, Texto pronto pra tela, ou "" se está tudo certo pra subir. A falta de chave não…

### Community 62 - "splashInicializacao.py"
Cohesion: 0.16
Nodes (9): _desenhar(), iniciar(), Janela de carregamento mostrada enquanto o sistema abre. Por que existe. Entre…, Cria a QApplication do processo e mostra a tela de carregamento. Devolve (app,…, Objeto de mentira usado quando não deu para criar a janela (sem ambiente…, Troca a linha de status e redesenha na hora. O processEvents() é o ponto todo:…, Fecha a tela de carregamento. `janela` (a janela principal, uma QWindow do QML)…, _SemSplash (+1 more)

### Community 63 - "_aplicar_estilo_remoto"
Cohesion: 0.15
Nodes (11): _aplicar_estilo_remoto(), limitar_tamanho_fonte(), _mesclar_campos(), _mesclar_ordem(), _posicao_padrao(), Aplica localmente um estilo de impressão recebido de outra máquina (gossip ou…, Grava de uma vez a configuração inteira vinda da tela (chamado ao sair da tela…, O tamanho em pixels dentro da faixa aceita, ou a base quando o valor não é um… (+3 more)

### Community 64 - "montadorIndiceRuas.py"
Cohesion: 0.23
Nodes (13): baixar_cidade(), _baixar_overpass(), _consulta_overpass(), consultar_correios(), _distancia_m(), ErroMontagem, _ponto(), Exception (+5 more)

### Community 65 - "enviar_para_impressora"
Cohesion: 0.50
Nodes (4): enviar_para_impressora(), Envia `conteudo` (bytes crus, já formatados em ESC/POS) para a fila de…, imprimir(), Envia `conteudo` (bytes crus, já formatados em ESC/POS) para a fila de…

### Community 66 - "contagemCaixa.py"
Cohesion: 0.27
Nodes (11): aplicar_remoto(), _caminho_arquivo(), carregar(), obter_dia(), Contagem manual de caixa por forma de pagamento (Cartão, Dinheiro, Pix), usada…, `{dataIso: {cartao, dinheiro, pix, idEvento}}` de todos os dias já contados…, O registro de `data_iso`, ou None se o dia nunca foi contado., Grava (sobrescrevendo) a contagem de `data_iso` e devolve o id da gravação.… (+3 more)

### Community 67 - "ClientesController"
Cohesion: 0.21
Nodes (6): ClientesController, pyqtSlot, QObject, O cadastro só funciona com a máquina numa rede (ver o topo)., O cliente deste telefone ({"telefone", "nome", "rua", "numero", "bairro",…, Cria ou sobrescreve o cliente com os dados da comanda de Entrega (cliente,…

### Community 68 - "dev_watch.py"
Cohesion: 0.24
Nodes (11): _arquivos_observados(), _encerrar_processo(), _esperar_workspace_da_janela(), _iniciar_processo(), main(), _mover_janela_para_workspace(), Roda main.py num subprocesso e reinicia automaticamente sempre que um arquivo…, Consulta o Hyprland pela janela do processo com esse pid e devolve o id do… (+3 more)

### Community 69 - "pareamento_teste.py"
Cohesion: 0.21
Nodes (10): ao_mudar_pareamento(), ao_pedido_de_entrada(), log(), Verifica o pareamento (entrada aprovada na rede) e o cadastro de clientes…, tick(), _argumentos_do_cadastro(), Verifica manualmente a sincronização do cadastro de usuários entre "máquinas" —…, Nome e código depois de --cadastrar, com padrão para quem esquecer. (+2 more)

### Community 70 - "._listar_mesas_locais"
Cohesion: 0.22
Nodes (4): Todas as mesas abertas gravadas localmente, como dicts completos (não só o…, Resumo de cada mesa aberta (mesa, cliente, total, qtd de itens), ordenado pelo…, Quando um peer NOVO entra na malha (quantidade aumentou, não só mudou),…, _valor_total_itens()

### Community 71 - "redeQml.py"
Cohesion: 0.18
Nodes (9): pyqt6, pyqt6_qtqml, QNetworkAccessManager, QQmlNetworkAccessManagerFactory, FabricaRedeQml, _GerenciadorComUserAgent, instalar(), User-Agent nos pedidos de rede feitos pelo QML. O engine QML baixa imagens… (+1 more)

### Community 72 - "normalizar"
Cohesion: 0.24
Nodes (12): normalizar(), Minúsculas e sem acento, que é a forma comparável de tudo aqui. Sem isto,…, adicionar(), _limpar(), marcar_correios(), preparar(), _normalizar_bairro(), _normalizar_rua() (+4 more)

### Community 73 - ".registrarEdicaoCaixa"
Cohesion: 0.23
Nodes (6): (codigo, cliente, valor) da comanda, lidos do .txt enquanto ele ainda existe.…, Anota que uma comanda JÁ FECHADA foi corrigida, para a linha sair no cupom de…, Anota que uma comanda JÁ FECHADA foi apagada de vez. Chamado por…, Grava e anuncia à malha — o que edição e exclusão têm em comum. O registro…, Anota uma edição ou exclusão de qualquer comanda — com baixa ou sem — para as…, AAAA-MM-DD" do dia da comanda, deduzido do nome do arquivo (que já embute a…

### Community 74 - "montar_linhas_por_ordem"
Cohesion: 0.22
Nodes (10): categoria_campo(), linhas_espacamento_secoes(), linhas_separador_antes(), Lista de linhas vazias usada como espaçador entre seções da comanda…, Quantas linhas de traço ("-" * 40) entram ANTES de `campo` numa comanda em que…, Categoria de `campo` (ver CATEGORIA_CAMPO) — "" para uma chave desconhecida, o…, linhas_modalidade(), montar_linhas_por_ordem() (+2 more)

### Community 75 - "titulo_em_raster"
Cohesion: 0.12
Nodes (18): _altura_da_linha(), _desenhar_separador(), _desenhar_titulo(), _despejar_palavra(), _largura_celula(), _nova_imagem(), _pintar_linhas(), _quebrar_em_linhas_fisicas() (+10 more)

### Community 76 - "graphify"
Cohesion: 0.29
Nodes (6): Atualização antes de todo commit, Consultas, graphify, pizzeria_system, Quando o usuário já rodou `git add .`, Regras gerais

### Community 77 - "impressoraWindows.py"
Cohesion: 0.29
Nodes (10): _configurar_porta_serial(), _executavel_powershell(), garantir_impressora_bematech(), _log(), _logar_resultado(), Automatiza, no Windows, a configuração da impressora térmica Bematech MP-4200…, Configura baud/paridade/bits/controle-de-fluxo da porta COM virtual via `mode`…, Localiza a Bematech MP-4200 TH nas portas USB e garante que existe uma fila de… (+2 more)

### Community 78 - ".listarRascunhos"
Cohesion: 0.18
Nodes (7): pyqtSlot, Descarta o rascunho — pelo × do card, ou porque ele virou comanda (ver…, Soma o valor dos itens do rascunho. Mesma conta de…, Um resumo por rascunho, do mais recente para o mais antigo — só o que o card da…, O rascunho inteiro, pronto para repovoar o formulário. {} quando ele não existe…, Grava e devolve o id (novo, se o registro veio sem um). "" quando a gravação…, _valor_total_itens()

### Community 79 - "subprocess"
Cohesion: 0.25
Nodes (10): _avisar(), main(), _pythons_candidatos(), _raiz_do_projeto(), Lançador do sistema para Windows — é isto que vira o .exe de duplo clique. Não…, Pasta onde está o main.py. Procura ao lado do executável e nos diretórios acima…, Interpretadores a tentar, do mais específico para o mais genérico. O venv do…, Mostra o erro numa caixa do Windows; no resto, imprime. Sem isto, um .exe… (+2 more)

### Community 80 - "MontagemExtras.js"
Cohesion: 0.27
Nodes (7): adicionaisDaLinha(), bordaDaLinha(), _comoObjeto(), formatarMoeda(), gravarNaLinha(), valorAjustado(), valorNum()

### Community 81 - "formatar_com_atributos"
Cohesion: 0.22
Nodes (9): _comando_tamanho_fonte(), _comando_tamanho_px(), fonte_impressao(), formatar_com_atributos(), _multiplicador_fonte(), Converte um tamanho em pixels no multiplicador ESC/POS mais próximo (1 a 8).…, GS !" espera um byte: bits 0-2 = altura-1, bits 4-6 = largura-1 — aqui sempre…, O mesmo embrulho de formatar_campo, com os atributos passados direto — para… (+1 more)

### Community 82 - "quebrar_linha"
Cohesion: 0.25
Nodes (8): largura_visivel(), _linhas_do_nome(), quebrar_linha(), quebrar_linhas(), quebrar_linha aplicada a uma lista, na ordem., A coluna do item em uma ou mais linhas: a primeira alinhada com o valor, as…, Quantas colunas do papel a linha ocupa — o texto sem os códigos de estilo, que…, `linha` em uma ou mais linhas de até `largura` colunas, sem partir palavra: a…

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

### Community 87 - "mesma_rua"
Cohesion: 0.33
Nodes (7): mesma_rua(), A mesma rua escrita de dois jeitos, com ou sem o tipo de via., Os CEPs que o ViaCEP conhece para a rua na cidade. A resposta traz toda rua que…, _sem_tipo(), ceps_da_rua(), corrigir_cep(), _viacep_logradouro()

### Community 88 - "rua_equivalente"
Cohesion: 0.29
Nodes (8): buscar_ruas(), _montar_busca(), _para_sugestao(), _preparar_busca(), As listas ordenadas que a busca binária percorre, e os bairros conhecidos com a…, Ruas cujo nome tem uma palavra começando por `termo` — [{"nome", "bairros",…, A rua do índice que é a mesma de `nome` — sem caixa, acento e pontuação, e com…, rua_equivalente()

### Community 89 - "._montar_recibo_extra"
Cohesion: 0.22
Nodes (4): FGTS.................... R$ 8,00" ocupando a linha inteira, com o valor…, ("23:26", "01/06/2026") a partir do "dd/mm/aaaa HH:MM:SS" gravado no lançamento…, Monta o recibo de pagamento de diária em bytes ESC/POS, pronto pra impressora,…, Pede a impressão do recibo pela malha local, igual a reimprimirComanda — o…

### Community 90 - "limpezaServidorAntigo.py"
Cohesion: 0.33
Nodes (8): _caminho_pid(), _eh_o_servidor(), executar(), _nome_do_processo(), _pasta_base(), Uma vez por abertura: encerra o ppgs_server que a versão anterior do sistema…, A mesma pasta que services/servidor/preparo.py usava., signal

### Community 91 - "fechamentoCache.py"
Cohesion: 0.33
Nodes (8): _caminho_arquivo(), carregar(), listar_dias(), _pasta_fechamentos(), Persistência do resumo de fechamento de caixa — um JSON por dia, na pasta de…, Resumo já salvo para `data_iso` ("AAAA-MM-DD"), ou None se esse dia nunca foi…, Datas ("AAAA-MM-DD") de todo dia já calculado/cacheado nesta máquina — usado…, salvar()

### Community 92 - "formatar_campo"
Cohesion: 0.16
Nodes (13): _item_sem_precos(), _linhas_itens_producao(), Tabela de itens da comanda do pizzaiolo — mesma montagem de grupos de…, Via de produção: mesa, cliente, hora e os itens — sem valor nenhum, nem por…, Cópia do item com os preços de borda e adicionais zerados. O valor do item em…, formatar_campo(), Envolve `texto` com os comandos ESC/POS ligados/desligados conforme a…, _acomodar_tamanho() (+5 more)

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

### Community 99 - "_itens_pendentes_cozinha"
Cohesion: 0.33
Nodes (6): _chave_item(), _itens_pendentes_cozinha(), _itens_reais(), Só os itens de verdade da mesa. O formulário do Salão sempre tem ao menos uma…, Identidade de um item para efeito de "já foi pra cozinha ou não". Duas pizzas…, Itens da mesa que ainda não foram impressos para o pizzaiolo. Uma comanda de…

### Community 100 - "faixa_de_numeros"
Cohesion: 0.29
Nodes (7): faixa_de_numeros(), _fim_do_par(), A UF do estabelecimento. O campo "uf" vem do índice de ruas, que nem sempre já…, Onde termina "766/767" (o lado par e o ímpar da mesma altura): no 767. O ViaCEP…, (início, fim, lado) dos números que um CEP de rua atende, lido do "complemento"…, _sem_acento(), uf_da_localizacao()

### Community 101 - "_mesclar_ajustes"
Cohesion: 0.50
Nodes (5): _limitar_linhas_separador(), _mesclar_ajustes(), _mesclar_separadores_campo(), Valida o mapa de exceções {campo: nº de linhas de traço antes dele}. Descarta…, Copia por cima de `destino` (já nos padrões) os ajustes de espaçamento e de…

### Community 102 - "StatusInicializacaoService"
Cohesion: 0.33
Nodes (3): QObject, Exposto ao QML como `statusController`., StatusInicializacaoService

### Community 110 - "Paleta Forno Design System"
Cohesion: 0.50
Nodes (4): Food Color Palette Reference, Paleta Forno Design System, Caprasimo Font License, Figtree Font License

### Community 115 - ".imprimirComandaExemplo"
Cohesion: 0.25
Nodes (7): _modalidade_do_exemplo(), _montar_linha_exemplo(), ordem_secoes(), Uma linha da comanda de exemplo, a partir dos trechos que a tela mandou (ver…, A modalidade da comanda de exemplo, deduzida dos campos que a prévia mandou —…, Imprime a comanda de exemplo da tela de Configurações, pra o dono conferir no…, Ordem atual dos campos na comanda impressa (lista de chaves de…

## Knowledge Gaps
- **18 isolated node(s):** `pizzeria-system`, `Consultas`, `Atualização antes de todo commit`, `Quando o usuário já rodou `git add .``, `Regras gerais` (+13 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 943 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **8 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `protegido()` connect `protegido` to `SugestoesEnderecoService`, `cardapioService.py`, `ConsultaController`, `UsuariosController`, `SalaoController`, `sugestoesEndereco.py`, `ValidacaoEnderecoController`, `ComandaEstiloController`, `comandaEstiloService.py`, `redeService.py`, `EstatisticasController`, `QTcpSocket`, `logConfig.py`, `pyqtSlot`, `os`, `._calcular_resumo_dia`, `EntregaController`, `PrinterService`, `.criarRede`, `_aplicar_estilo_remoto`, `ClientesController`, `._listar_mesas_locais`, `.registrarEdicaoCaixa`, `.listarRascunhos`, `._montar_recibo_extra`, `.imprimirComandaExemplo`?**
  _High betweenness centrality (0.214) - this node is a cross-community bridge._
- **Why does `RedeService` connect `RedeService` to `pyqtSlot`, `pyqtProperty`, `._imprimir_localmente_e_notificar`, `BarramentoEventos`, `._tentar_conectar_a_peer`, `.criarRede`, `redeService.py`, `PrinterService`, `._processar_mensagem`, `QTcpSocket`?**
  _High betweenness centrality (0.097) - this node is a cross-community bridge._
- **Why does `FechamentoController` connect `FechamentoController` to `._montar_recibo_extra`, `os`, `.registrarEdicaoCaixa`, `._calcular_resumo_dia`, `protegido`?**
  _High betweenness centrality (0.092) - this node is a cross-community bridge._
- **Are the 2 inferred relationships involving `RedeService` (e.g. with `PrinterService` and `BarramentoEventos`) actually correct?**
  _`RedeService` has 2 INFERRED edges - model-reasoned connections that need verification._
- **What connects `pizzeria-system`, `Consultas`, `Atualização antes de todo commit` to the rest of the system?**
  _18 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `SugestoesEnderecoService` be split into smaller, more focused modules?**
  _Cohesion score 0.05010351966873706 - nodes in this community are weakly interconnected._
- **Should `seguranca.py` be split into smaller, more focused modules?**
  _Cohesion score 0.060655737704918035 - nodes in this community are weakly interconnected._