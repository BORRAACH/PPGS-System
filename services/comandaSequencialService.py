"""Código curto impresso no cabeçalho de cada comanda (ver
controllers/balcaoController.py, entregaController.py, salaoController.py)
— não é o identificador de verdade de uma comanda (isso continua sendo o
nome do arquivo, único por timestamp+sufixo aleatório, ver cada
controller), é só um código fácil de ler/falar/anotar em papel.

Cada caractere carrega uma informação (ver gerar_codigo_pedido): a máquina
onde o pedido foi lançado, o dia e a hora, e por último a ordem de chegada
do pedido NA MALHA no dia — reiniciada a cada dia novo.

A letra da máquina vem da ordem de conexão ATUAL na malha local (ver
RedeService.letraLocal em services/rede/redeService.py) — não da inicial do
hostname: duas máquinas podiam ter hostname começando pela mesma letra,
colidindo. Não é um identificador fixo por máquina: uma máquina que
desconecta e reconecta entra de novo no fim da fila (pega a próxima letra
livre no momento), em vez de reter a posição de antes da queda. A leitura em
si é 100% local (nunca espera resposta de rede) — usa só o que RedeService já
tem em memória sobre os peers conectados agora.

O NÚMERO do dia segue a linha de eventos da MALHA, não a ordem interna de
cada máquina: uma comanda lançada em A sai 01, a próxima lançada em B sai 02,
a seguinte sai 03, independente de onde foi lançada. Antes cada máquina
contava sozinha num arquivo local, e numa noite normal todas elas imprimiam
01, 02, 03 — o número dizia respeito ao terminal, não à loja.

Isso é feito SEM máquina líder e SEM esperar a rede, que continua sendo a
regra inegociável aqui (mesmo princípio de RedeService.solicitar_impressao ser
assíncrono: uma operação local nunca deve travar por causa da rede). O número
sai de um registro compartilhado de reservas — services/rede/sequenciaComandas.py
— que cada máquina lê e grava localmente e anuncia por gossip depois; o
anúncio chega às outras em ~1 salto, muito antes de alguém conseguir digitar a
comanda seguinte.

O que isso deliberadamente NÃO garante é unicidade absoluta do número: uma
máquina particionada da malha (cabo caiu, acabou de abrir) numera a partir do
que ela conhece e pode repetir um número que outra já usou — travar a venda
até a rede responder seria pior. Como a letra da máquina entra no código, dois
pedidos nunca saem com o código idêntico nem nesse caso. É a mesma garantia de
antes; a diferença é que a repetição virou exceção em vez de regra."""

from services.rede import rede


def gerar_codigo_pedido(agora):
    """Código de 7 caracteres pro cabeçalho da comanda impressa, a partir
    do `agora` (datetime) já usado por quem chama para o campo "Data:" —
    recebido como parâmetro em vez de chamar datetime.now() de novo aqui,
    pra nunca poder divergir do horário realmente impresso na comanda:

    - 1 letra: ordem de conexão ATUAL desta máquina na malha local (ver
      RedeService.letraLocal em services/rede/redeService.py) — A para a
      primeira máquina conectada agora, B para a segunda, etc.
    - 2 dígitos: dia do mês.
    - 2 dígitos: hora (24h).
    - 2 dígitos: ordem de chegada do pedido na malha hoje (01, 02...).

    Ex: "C291401" = 3ª máquina conectada na malha agora, dia 29, 14h, 1º
    pedido lançado na malha inteira no dia.

    Acima de 99 o número simplesmente cresce e o código passa a ter 8
    caracteres ("A181599" é o 99º; o 100º é "A1815100"): nada que leia o
    código assume largura fixa (ver comandaParserService.PADRAO_ID_PEDIDO), e
    truncar de volta pra 01 faria dois pedidos do mesmo dia terem o mesmo
    número. Passar de 99 num dia ficou plausível justamente porque agora a
    contagem é da malha inteira, não de uma máquina só."""
    maquina = rede.letraLocal
    numero = rede.reservar_numero_comanda(agora.date().isoformat())
    return f"{maquina}{agora.day:02d}{agora.hour:02d}{numero:02d}"
