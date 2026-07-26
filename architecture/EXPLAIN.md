# Sincronização de pedidos entre 4 máquinas via rede local (P2P)

## Contexto

O sistema roda em 4 computadores simultaneamente, cada um tirando pedidos
(Balcão/Entrega) de forma independente. Hoje cada pedido vira um `.txt` em
`<raiz>/pedidos/` **local** à máquina que o criou, e `Consulta.qml` só lê a
pasta local da própria máquina — então um pedido tirado no computador A é
invisível em `Consulta.qml` no computador B.

O pedido é: quando o app abre em qualquer uma das 4 máquinas, ele deve achar
sozinho as outras instâncias abertas na mesma rede local e passar a
compartilhar os pedidos entre si, sem nenhuma máquina "central" fixa —
confirmado com o usuário: **topologia em malha (P2P)**, onde cada instância
aberta se conecta diretamente às outras 3 (se uma fechar, as demais
continuam sincronizadas normalmente entre si), e a tela de Consulta deve
**atualizar sozinha, na hora**, assim que um pedido chega pela rede — sem
precisar clicar em "Atualizar".

Como só há 4 máquinas, dá pra usar malha *completa* (cada uma conectada
diretamente a todas as outras) em vez de um protocolo de retransmissão/gossip
com múltiplos saltos — isso elimina a necessidade de lógica de
retransmissão e de prevenção de loop, simplificando bastante o protocolo.

## Arquitetura

**Descoberta (mDNS/DNS-SD, via zeroconf)** + **canal de dados (TCP, malha
completa)**. O canal de dados usa só `PyQt6.QtNetwork`; a descoberta usa a
biblioteca `zeroconf` (ver `preConfig.py`), com um plano B em UDP broadcast
para quando ela não estiver instalada.

As duas metades ficam em arquivos separados dentro de `services/rede/`:
`descoberta.py` só responde "quem está na rede e em que endereço", e
`redeService.py` cuida da malha, do protocolo e da eleição da impressora.

1. Cada instância abre um `QTcpServer` numa porta efêmera (porta 0 → o SO
   escolhe) e, só depois de saber essa porta, começa a se anunciar.
2. O anúncio é um serviço DNS-SD do tipo `_pizzaria-rede._tcp.local.`, com a
   porta TCP e as propriedades `{"assinatura": "PIZZARIA_REDE_V1", "id":
   <uuid da instância>}`. O tipo de serviço já isola nossas instâncias do
   resto do que se anuncia na rede (impressoras, TVs, outros programas). O
   nome do serviço e o do host usam o uuid da instância, e não o hostname da
   máquina, porque duas instâncias podem rodar no mesmo computador (é o caso
   dos scripts em `docker/`) e uma sobrescreveria o anúncio da outra.
3. O `ServiceBrowser` avisa quando um serviço aparece; resolver endereço e
   porta é feito numa thread à parte (bloquear a thread do zeroconf com o
   `get_service_info()` dela mesma travaria a resposta que se está
   esperando). O resultado volta pra thread principal pelo sinal
   `peerDescoberto`, e só então o `RedeService` decide o que fazer: ignora a
   si mesmo e quem já é peer, e, entre os dois lados, só o de `id` "menor"
   (comparação de string) inicia a conexão TCP — evita conexão dupla entre o
   mesmo par.
4. Nova conexão TCP → troca de handshake
   (`{"tipo": "identificar", "id": ..., "nome": ..., "temImpressora": bool}`)
   e, em seguida, cada lado manda `{"tipo": "meus_arquivos", "arquivos": [...]}`
   (lista de nomes de arquivo em `pedidos/`). Quem recebe compara com a
   própria pasta e pede (`{"tipo": "pedir_arquivo", "arquivo": ...}`) o que
   não tem — isso resolve o catch-up de quem estava offline/atrasado.
5. Mensagens (JSON + `"\n"`, um por linha, num buffer por socket):
   - `pedido` — `{"tipo": "pedido", "arquivo": nome, "conteudo_b64": ...}`
   - `apagar` — `{"tipo": "apagar", "arquivo": nome}`
   - `status_impressora` — `{"tipo": "status_impressora", "temImpressora": bool}`,
     mandada pra todos os peers sempre que a checagem periódica da
     impressora local (a cada 30s, além de uma vez ao abrir) muda de
     resultado — ver "Impressão pela rede" abaixo.
   - `imprimir` — `{"tipo": "imprimir", "job_id": ..., "conteudo_b64": ...}`,
     mandada só pra máquina eleita pra imprimir (nunca em broadcast).
   - `imprimir_resultado` — `{"tipo": "imprimir_resultado", "job_id": ..., "sucesso": bool, "erro": str, "maquina": nome}`,
     resposta ao `imprimir`, sempre pro mesmo socket de onde veio o pedido.
   - Como é malha completa, **não há retransmissão**: quem cria/apaga um
     pedido manda a mensagem direto para todos os peers conectados; quem
     recebe só aplica local (grava/apaga o arquivo), nunca repassa adiante.
6. Ao desconectar um peer, ele só é removido de `_peers` — quando ele voltar,
   o anúncio dele reaparece na rede e a reconexão acontece sozinha. Se o
   peer removido era a máquina eleita pra imprimir, a eleição é recalculada
   na hora.

### Impressão pela rede

Cada instância tenta detectar sua própria impressora local ao iniciar (e a
cada 30s depois, numa thread — `PrinterService.localizar_impressora()` roda
`lpstat`/PowerShell) e anuncia o resultado (`temImpressora`) tanto no
handshake `identificar` quanto, se mudar depois, via `status_impressora`.

Toda instância calcula, sozinha e de forma determinística — sem nenhuma
mensagem de "eleição" própria —, qual máquina deve receber os pedidos de
impressão (`RedeService._recalcular_maquina_impressora`): a própria máquina,
se tiver impressora; senão, entre os peers conhecidos que anunciaram ter,
o de menor `id`. Como todo mundo vê o mesmo conjunto de anúncios, todo mundo
chega à mesma conclusão sem precisar de coordenador central.

`RedeService.solicitar_impressao(conteudo_bytes)` (chamada pelos
controllers em vez de `PrinterService.imprimir()` direto) manda `imprimir`
só pra essa máquina eleita (local ou remota) e aguarda `imprimir_resultado`
com um timeout de 10s. O resultado final chega pra quem pediu via o sinal
`impressaoResultado(sucesso, detalhe)`, exposto ao QML como
`redeController.impressaoResultado` — `main.qml` mostra uma notificação
global com o resultado, já que pode chegar segundos depois e o usuário pode
já ter saído da tela onde pediu a impressão.

### Arquivo novo: `services/rede/descoberta.py`

- Só descoberta: quem está na rede local e em que endereço/porta. Nada de
  malha, protocolo ou impressora — isso é do `redeService.py`.
- `criar_descoberta(parent)` devolve a melhor estratégia disponível:
  `DescobertaZeroconf` (padrão) ou `DescobertaBroadcast` (plano B, quando a
  biblioteca `zeroconf` não está instalada). As duas herdam de `Descoberta`,
  que define a interface comum: `iniciar(id_local, porta_tcp)`, `parar()` e
  o sinal `peerDescoberto(id, endereco, porta_tcp)`.
- A descoberta avisa de tudo que encontra — inclusive da própria máquina e
  de peers repetidos. Filtrar é responsabilidade de quem recebe, que é quem
  sabe com quem já tem conexão aberta.
- `parar()` é ligado sozinho ao `aboutToQuit` da aplicação: o anúncio
  precisa sair da rede ao fechar, senão as outras máquinas ficam tentando
  discar pra uma instância morta até o registro expirar.

### Arquivo novo: `services/rede/redeService.py`

- Classe `RedeService(QObject)`, instanciada uma vez como singleton de
  módulo (`rede = RedeService()`), no padrão dos serviços existentes
  (`services/printerService.py`).
- Não toca em disco — só rede. Expõe:
  - `pyqtSignal pedidoRecebido(str, "QByteArray")` — nome do arquivo, bytes.
  - `pyqtSignal pedidoRemovidoRemoto(str)` — nome do arquivo.
  - `pyqtSignal peersMudaram(int)` + `pyqtProperty(int)` com a contagem de
    peers conectados (pra um indicador simples na tela).
  - `iniciar()` — abre o servidor TCP e dispara a descoberta; **precisa ser
    chamado depois que `QGuiApplication` já existe** (main.py, depois do
    `engine = QQmlApplicationEngine()`).
  - `transmitir_pedido(nome_arquivo: str, conteudo_bytes: bytes)` e
    `transmitir_exclusao(nome_arquivo: str)` — chamadas pelos controllers.
  - `solicitar_impressao(conteudo_bytes: bytes)` e `pyqtSignal impressaoResultado(bool, str)`
    — ver seção "Impressão pela rede" acima.

### Mudanças nos controllers existentes

- `controllers/balcaoController.py` (`enviarPedido`, por volta da linha
  116-122) e `controllers/entregaController.py` (`enviarPedido`, por volta
  da linha 129): logo depois de `arquivo.write(conteudo_bytes)` bem-sucedido,
  chamar `rede.transmitir_pedido(nome_arquivo, conteudo_bytes)`.
- **Correção necessária no nome do arquivo**: hoje é
  `pedido_{timestamp-com-resolução-de-segundo}.txt`
  (`balcaoController.py:85`, `entregaController.py:90`). Com 4 máquinas
  gravando ao mesmo tempo, dois pedidos no mesmo segundo colidem e um
  sobrescreve o outro depois de sincronizado. Vou acrescentar um sufixo curto
  único (`uuid.uuid4().hex[:6]`) ao nome, nas duas controllers — não afeta
  `consultaController.py` (que só olha o prefixo `pedido_`/`entrega_` e o
  conteúdo, nunca o timestamp do nome).
- `controllers/consultaController.py`:
  - Adicionar `pyqtSignal comandasAtualizadas()` na classe.
  - Adicionar `aplicarPedidoRemoto(nome_arquivo, conteudo: QByteArray)` —
    grava `bytes(conteudo)` em `pasta_pedidos/nome_arquivo` e emite o sinal.
  - Adicionar `removerPedidoRemoto(nome_arquivo)` — `os.remove` (se existir)
    e emite o sinal.
  - Em `apagarComanda` (linha 236-247), depois do `os.remove` bem-sucedido,
    chamar `rede.transmitir_exclusao(nome_arquivo)`.

### `main.py`

Depois de criar `consultaController` e registrá-lo como context property:

```python
from services.rede import rede

rede.pedidoRecebido.connect(consultaController.aplicarPedidoRemoto)
rede.pedidoRemovidoRemoto.connect(consultaController.removerPedidoRemoto)
engine.rootContext().setContextProperty("redeController", rede)
rede.iniciar()
```

### `qml/pages/consulta/Consulta.qml`

- Linha 148 (`Component.onCompleted: carregarComandas()`): também conectar
  `consultaController.comandasAtualizadas.connect(carregarComandas)` — assim
  a lista atualiza sozinha quando um pedido chega pela rede, sem precisar do
  botão.
- Pequeno indicador ao lado de `btnAtualizar` (linha ~187): um `Text` com
  `"🌐 " + redeController.quantidadeConectados + " conectado(s)"`, pra dar
  visibilidade de que a sincronização está de fato funcionando (peça
  invisível por natureza — vale o custo baixo de adicionar).

## Fora do escopo (mencionar, não implementar agora)

- Sem autenticação/senha para entrar na rede — qualquer instância deste app
  na mesma LAN entra automaticamente, conforme pedido pelo usuário.
- Sem migração do formato de arquivo (`.txt` com códigos ESC/POS) para
  JSON/SQLite — a réplica é feita nos bytes crus do arquivo, mantendo o
  formato atual intacto. (A impressão em si passou a ser roteada pela rede —
  ver "Impressão pela rede" acima — mas o formato do arquivo não mudou.)
- Firewall do SO pode pedir liberação de rede na primeira execução em cada
  máquina (normal, principalmente no Windows) — não é algo a resolver em
  código.

## Verificação

Não dá pra testar em 4 máquinas físicas neste ambiente, então a verificação
será:

1. Rodar duas instâncias de `main.py` no mesmo host (dois processos,
   `QT_QPA_PLATFORM=offscreen`), simulando 2 "computadores" — o mDNS
   enxerga os dois processos locais normalmente.
2. Confirmar que os dois processos se descobrem e conectam (via log ou
   contagem de peers).
3. Chamar `balcaoController.enviarPedido(...)` no processo A (via um
   pequeno script de teste) e confirmar que o `.txt` aparece em `pedidos/`
   no processo B, e que `consultaController.listarComandas()` no processo B
   já retorna esse pedido.
4. `qmllint` no `Consulta.qml` alterado.
