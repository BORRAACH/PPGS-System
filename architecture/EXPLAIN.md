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

**Descoberta (UDP broadcast)** + **canal de dados (TCP, malha completa)**,
usando só `PyQt6.QtNetwork` (já vem com o PyQt6 — nenhuma dependência nova em
`preConfig.py`).

1. Cada instância abre um `QTcpServer` numa porta efêmera (porta 0 → o SO
   escolhe) e um `QUdpSocket` fixo (porta de descoberta) em modo broadcast.
2. A cada ~5s (e uma vez ao iniciar), cada instância manda um datagrama UDP
   broadcast (`255.255.255.255`) com um JSON `{"assinatura": "PIZZARIA_REDE_V1",
   "id": <uuid da instância>, "porta_tcp": <porta do QTcpServer>}`. A
   assinatura garante que só instâncias deste app entram na rede (tráfego de
   outros dispositivos na LAN é ignorado).
3. Ao receber um datagrama de outra instância que ainda não é peer, só o lado
   com o `id` "menor" (comparação de string) inicia a conexão TCP — evita
   conexão dupla entre o mesmo par.
4. Nova conexão TCP → troca de handshake (`{"tipo": "identificar", "id": ...}`)
   e, em seguida, cada lado manda `{"tipo": "meus_arquivos", "arquivos": [...]}`
   (lista de nomes de arquivo em `pedidos/`). Quem recebe compara com a
   própria pasta e pede (`{"tipo": "pedir_arquivo", "arquivo": ...}`) o que
   não tem — isso resolve o catch-up de quem estava offline/atrasado.
5. Mensagens (JSON + `"\n"`, um por linha, num buffer por socket):
   - `pedido` — `{"tipo": "pedido", "arquivo": nome, "conteudo_b64": ...}`
   - `apagar` — `{"tipo": "apagar", "arquivo": nome}`
   - Como é malha completa, **não há retransmissão**: quem cria/apaga um
     pedido manda a mensagem direto para todos os peers conectados; quem
     recebe só aplica local (grava/apaga o arquivo), nunca repassa adiante.
6. Ao desconectar um peer, ele só é removido de `_peers` — a redescoberta via
   broadcast periódico cuida da reconexão automática quando ele voltar.

### Arquivo novo: `services/redeService.py`

- Classe `RedeService(QObject)`, instanciada uma vez como singleton de
  módulo (`rede = RedeService()`), no padrão dos serviços existentes
  (`services/printerService.py`).
- Não toca em disco — só rede. Expõe:
  - `pyqtSignal pedidoRecebido(str, "QByteArray")` — nome do arquivo, bytes.
  - `pyqtSignal pedidoRemovidoRemoto(str)` — nome do arquivo.
  - `pyqtSignal peersMudaram(int)` + `pyqtProperty(int)` com a contagem de
    peers conectados (pra um indicador simples na tela).
  - `iniciar()` — abre os sockets e o timer de broadcast; **precisa ser
    chamado depois que `QGuiApplication` já existe** (main.py, depois do
    `engine = QQmlApplicationEngine()`).
  - `transmitir_pedido(nome_arquivo: str, conteudo_bytes: bytes)` e
    `transmitir_exclusao(nome_arquivo: str)` — chamadas pelos controllers.

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
from services.redeService import rede

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
  formato atual intacto (inclusive para impressão, que continua só local).
- Firewall do SO pode pedir liberação de rede na primeira execução em cada
  máquina (normal, principalmente no Windows) — não é algo a resolver em
  código.

## Verificação

Não dá pra testar em 4 máquinas físicas neste ambiente, então a verificação
será:

1. Rodar duas instâncias de `main.py` no mesmo host (dois processos,
   `QT_QPA_PLATFORM=offscreen`), simulando 2 "computadores" — o broadcast UDP
   em `255.255.255.255` chega nos dois processos locais.
2. Confirmar que os dois processos se descobrem e conectam (via log ou
   contagem de peers).
3. Chamar `balcaoController.enviarPedido(...)` no processo A (via um
   pequeno script de teste) e confirmar que o `.txt` aparece em `pedidos/`
   no processo B, e que `consultaController.listarComandas()` no processo B
   já retorna esse pedido.
4. `qmllint` no `Consulta.qml` alterado.
