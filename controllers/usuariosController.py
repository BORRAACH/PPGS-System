"""Cadastro de usuários e o guarda das ações destrutivas.

Duas responsabilidades que andam juntas: manter o cadastro replicado
(services/rede/usuarios.py, mesmo desenho de domínio sincronizado dos
extras) e ser o único caminho por onde uma ação protegida é liberada
(`validarCodigo`, chamado por qml/components/PopupAutorizacao.qml).

Controller próprio, e não um método enfiado no FechamentoController ou no
ConsultaController: as duas telas consomem isto ao mesmo tempo, e pendurar
o cadastro em uma delas faria a outra depender do controller de uma tela
sem relação nenhuma com usuários.

O que este guarda protege, dito sem eufemismo: a equipe do balcão. Dois
dígitos são cem combinações e a malha não autentica ninguém (ver o topo de
services/rede/usuarios.py). Ele responde "quem editou esta comanda?" e
obriga um ato deliberado antes de uma edição destrutiva — não impede quem
quiser insistir.

E o CADASTRO em si é trancado por outra coisa: a senha do dono
(services/rede/senhaDono.py), pedida na tela de Usuários e nunca no balcão.
São dois segredos com papéis opostos de propósito — o código de dois dígitos
existe para ser digitado na frente de todo mundo (é assinatura, não segredo),
e a senha existe para não ser. Se o código do dono também abrisse o cadastro,
bastaria decorá-lo vendo-o ser digitado para se cadastrar sozinho.

A tranca mora AQUI, e não só na tela: os três slots que mexem no cadastro
conferem a senha eles mesmos (`_autorizar_escrita`), então uma tela que
esquecesse de perguntar não conseguiria gravar nada mesmo assim. E é por
gravação, não por sessão — cadastrar, editar e remover pedem a senha cada um
na sua vez."""

import time
from datetime import datetime

from PyQt6.QtCore import QObject, pyqtSignal, pyqtSlot

from Config.logConfig import protegido
from services.rede import (edicoesCaixa, historicoEventos, rede, relogio, senhaDono,
                           tombstones, usuarios)

# Cadastro E edição viajam no mesmo tipo de evento, como "extra_lancado" —
# quem recebe decide se é criação ou revisão olhando se já conhece o id (ver
# _registrar_usuario_aprendido).
_EVENTO_USUARIO_ALTERADO = "usuario_alterado"
_EVENTO_USUARIO_APAGADO = "usuario_apagado"

# A senha do dono trocada nesta máquina, anunciada à malha (ver
# services/rede/senhaDono.py). Viaja o HASH, nunca a senha — não existe lugar
# nenhum, em disco ou em memória, onde ela esteja em claro depois de definida.
_EVENTO_SENHA_DONO_ALTERADA = "senha_dono_alterada"

# Quanto tempo a tela fica VISÍVEL depois de a senha ser aceita na porta.
#
# Só a vista: gravar pede a senha de novo, uma vez por gravação (ver
# _autorizar_escrita). Antes este prazo também valia como permissão de escrita,
# e isso queria dizer que uma tela deixada aberta era uma janela de cinco
# minutos para cadastrar um usuário — que é um código que apaga comandas.
#
# O prazo continua existindo porque a lista mostra nomes e a ficha mostra
# códigos: deixar isso à vista a tarde inteira depois que o dono saiu é o que
# ele evita.
_DURACAO_DESTRAVE_SEGUNDOS = 300


class UsuariosController(QObject):
    # Como em todo controller daqui, o sinal existe para o que chega de OUTRA
    # máquina. Uma ação feita aqui devolve o resultado pelo próprio slot, e a
    # tela reage ao retorno — emitir nos dois casos faria a lista recarregar
    # duas vezes por cadastro.
    usuariosAtualizados = pyqtSignal()

    # Emitido quando a senha do dono é definida ou trocada em OUTRA máquina.
    # A tela reage TRANCANDO: a senha que destravou esta sessão não é mais a
    # senha válida, e continuar aberto seria manter destrancado com um
    # segredo que já não vale.
    senhaDonoAtualizada = pyqtSignal()

    def __init__(self):
        super().__init__()

        # Instante (relógio monotônico) até o qual o cadastro aceita escrita.
        # Zero = trancado, que é como toda sessão começa — inclusive depois de
        # o app ser reaberto, já que isto nunca vai para o disco.
        self._destravado_ate = 0.0

        rede.registrarEvento(_EVENTO_USUARIO_ALTERADO, self._ao_receber_usuario_remoto)
        rede.registrarEvento(_EVENTO_USUARIO_APAGADO, self._ao_receber_usuario_apagado_remoto)
        rede.registrarEvento(_EVENTO_SENHA_DONO_ALTERADA, self._ao_receber_senha_remota)

        rede.registrarDominioSincronizado(
            usuarios.DOMINIO,
            self._resumo_usuarios,
            self._obter_usuario_reconciliacao,
            self._aplicar_usuario_reconciliacao,
            self._apagar_usuario_reconciliacao,
        )
        # Sem callback de exclusão de propósito: a senha não é apagável pela
        # malha, senão apagar o arquivo numa máquina destrancaria todas (ver
        # "ESQUECEU A SENHA" no topo de services/rede/senhaDono.py).
        rede.registrarDominioSincronizado(
            senhaDono.DOMINIO,
            senhaDono.resumo,
            senhaDono.obter,
            self._aplicar_senha_reconciliacao,
        )

    # ---------- Anti-entropy (ver services/rede/redeService.py:registrarDominioSincronizado) ----------

    def _resumo_usuarios(self):
        """Sem janela temporal, ao contrário de "extras"/"fechamento": um
        cadastro não é um fato datado que para de importar depois de 30 dias
        — o funcionário contratado no ano passado continua valendo hoje. E o
        conjunto é de dezenas de itens, então comparar tudo a cada ciclo é
        barato."""
        itens = {}
        for id_evento, registro in usuarios.carregar().items():
            itens[id_evento] = registro.get("idEventoRevisao", id_evento)
        return {"itens": itens, "apagados": tombstones.carregar(usuarios.DOMINIO)}

    def _obter_usuario_reconciliacao(self, id_evento):
        registro = usuarios.carregar().get(id_evento)
        if not registro:
            return None
        return dict(registro, id=id_evento)

    def _aplicar_usuario_reconciliacao(self, id_evento, payload):
        self._registrar_usuario_aprendido(id_evento, payload or {})

    def _apagar_usuario_reconciliacao(self, id_evento):
        # tombstones.mesclar já gravou o tombstone (com o id de quem apagou)
        # antes de chamar aqui — mesmo padrão de
        # FechamentoController._apagar_extra_reconciliacao.
        quando = tombstones.carregar(usuarios.DOMINIO).get(id_evento, "")
        self._aplicar_exclusao_usuario(id_evento, quando)

    # ---------- Gossip (caminho rápido) ----------

    def _ao_receber_usuario_remoto(self, payload):
        """Reação ao gossip "usuario_alterado" — para um cadastro novo OU uma
        correção feita em outra máquina aparecer aqui na hora, sem esperar o
        próximo ciclo de reconciliação."""
        payload = payload or {}
        id_evento = payload.get("id")
        if id_evento:
            self._registrar_usuario_aprendido(id_evento, payload)

    def _ao_receber_usuario_apagado_remoto(self, payload):
        payload = payload or {}
        id_evento = payload.get("id")
        if id_evento:
            self._aplicar_exclusao_usuario(id_evento, payload.get("quando", ""))

    def _registrar_usuario_aprendido(self, id_evento, payload):
        """Grava um usuário aprendido de fora, venha ele do gossip ou da
        reconciliação — os dois caminhos desembocam aqui, que é o que
        garante que convergem para o mesmo estado."""
        if id_evento in tombstones.carregar(usuarios.DOMINIO):
            # Demitido. O gossip da exclusão pode ter chegado antes do
            # cadastro (a ordem de entrega não é garantida), e sem esta
            # guarda ele voltaria para a lista.
            return

        if id_evento in usuarios.carregar():
            mudou = usuarios.aplicar_edicao_remota(
                id_evento,
                payload.get("codigo", ""),
                payload.get("nome", ""),
                payload.get("idEventoRevisao", ""),
            )
        else:
            usuarios.registrar(
                payload.get("codigo", ""),
                payload.get("nome", ""),
                payload.get("dataHora", ""),
                quando=id_evento,
            )
            mudou = True

        if mudou:
            self.usuariosAtualizados.emit()

    def _aplicar_exclusao_usuario(self, id_evento, quando):
        usuarios.apagar(id_evento, quando=quando or None)
        self.usuariosAtualizados.emit()

    # ---------- Cadastro (tela de Configurações) ----------

    @pyqtSlot(result="QVariantList")
    @protegido([])
    def listarUsuarios(self):
        """Todos os usuários, ordenados por nome, cada um com "duplicado":
        True quando outra pessoa usa o mesmo código. A tela marca essas
        linhas — ver o comentário sobre colisão em services/rede/usuarios.py.
        É calculado aqui, e não gravado, porque depende do conjunto inteiro e
        muda sozinho quando o outro lado da colisão é corrigido."""
        itens = usuarios.listar()
        vezes = {}
        for item in itens:
            codigo = item.get("codigo", "")
            vezes[codigo] = vezes.get(codigo, 0) + 1
        for item in itens:
            item["duplicado"] = vezes.get(item.get("codigo", ""), 0) > 1
        return itens

    @pyqtSlot(str, result="QVariantMap")
    @protegido({})
    def detalhesUsuario(self, id_evento):
        """Tudo que se sabe sobre uma pessoa do cadastro, para o popup que abre
        ao clicar na linha dela: nome, código, quando entrou, se o código está
        repetido, e o que ela já fez.

        Reunido AQUI, e não montado na tela a partir de três chamadas: a tela
        não deveria precisar saber que "ações autorizadas" mora no histórico da
        malha e "alterações no caixa" noutro domínio. {} quando o id não existe
        mais (removida em outra máquina enquanto a lista estava aberta).

        As duas contagens medem coisas DIFERENTES de propósito, e a tela diz
        isso: as autorizações são as dos últimos dias (a janela de retenção do
        histórico), e as alterações de caixa são de sempre — ver as docstrings
        de historicoEventos.contar_autorizacoes e edicoesCaixa.contar_do_usuario."""
        registro = usuarios.carregar().get(id_evento)
        if registro is None:
            return {}

        nome = registro.get("nome", "")
        codigo = registro.get("codigo", "")
        autorizacoes, id_ultima = historicoEventos.contar_autorizacoes(nome)

        return {
            "id": id_evento,
            "nome": nome,
            "codigo": codigo,
            "dataHora": registro.get("dataHora", ""),
            # Mesmo cálculo de listarUsuarios: depende do conjunto inteiro e
            # muda sozinho quando o outro lado da colisão é corrigido.
            "duplicado": len([item for item in usuarios.por_codigo(codigo) if item["id"] != id_evento]) > 0,
            "autorizacoes": autorizacoes,
            "diasHistorico": historicoEventos.RETENCAO_DIAS,
            # Instante em segundos desde a época, ou 0 — a tela formata.
            "ultimaAutorizacao": relogio.instante_do_id(id_ultima) if id_ultima else 0,
            "alteracoesCaixa": edicoesCaixa.contar_do_usuario(nome),
        }

    @pyqtSlot(result=bool)
    @protegido(False)
    def haUsuarios(self):
        return usuarios.existe_algum()

    @pyqtSlot(str, str, str, result="QVariantMap")
    @protegido({})
    def cadastrarUsuario(self, nome, codigo, senha):
        """Cadastra e devolve o registro gravado (com "id"), ou
        {"erro": ...} explicando o que impediu. Erros possíveis:
        "nome_vazio", "codigo_invalido" (não são dois dígitos), "codigo_em_uso"
        e "senha_incorreta" (ver _autorizar_escrita).

        A senha é conferida ANTES de qualquer validação de nome/código: quem
        não sabe a senha não deve aprender, pelas mensagens de erro, se um
        código já está em uso ou de quem ele é."""
        if not self._autorizar_escrita(senha, "cadastrar_usuario"):
            return {"erro": "senha_incorreta"}

        nome = (nome or "").strip()
        codigo = usuarios.normalizar_codigo(codigo)
        if not nome:
            return {"erro": "nome_vazio"}
        if not codigo:
            return {"erro": "codigo_invalido"}

        # Checagem de conveniência, não garantia: ela pega o caso real (o dono
        # cadastrando com a malha no ar) mas não tem como cobrir duas máquinas
        # particionadas cadastrando o mesmo código. Esse caso é resolvido pela
        # união dos registros e pelo aviso de duplicado na tela.
        ocupado = usuarios.por_codigo(codigo)
        if ocupado:
            return {"erro": "codigo_em_uso", "nome": ocupado[0].get("nome", "")}

        data_hora = datetime.now().strftime("%d/%m/%Y %H:%M:%S")
        id_evento = usuarios.registrar(codigo, nome, data_hora)
        self._publicar_usuario(id_evento)
        return dict(usuarios.carregar().get(id_evento, {}), id=id_evento)

    @pyqtSlot(str, str, str, str, result="QVariantMap")
    @protegido({})
    def editarUsuario(self, id_evento, nome, codigo, senha):
        """Corrige nome/código de quem já existe. Mesmos erros de
        cadastrarUsuario, mais "nao_encontrado"."""
        if not self._autorizar_escrita(senha, "editar_usuario"):
            return {"erro": "senha_incorreta"}

        nome = (nome or "").strip()
        codigo = usuarios.normalizar_codigo(codigo)
        if not nome:
            return {"erro": "nome_vazio"}
        if not codigo:
            return {"erro": "codigo_invalido"}
        if id_evento not in usuarios.carregar():
            return {"erro": "nao_encontrado"}

        ocupado = [item for item in usuarios.por_codigo(codigo) if item["id"] != id_evento]
        if ocupado:
            return {"erro": "codigo_em_uso", "nome": ocupado[0].get("nome", "")}

        if usuarios.editar(id_evento, codigo, nome) is None:
            return {"erro": "nao_encontrado"}

        self._publicar_usuario(id_evento)
        return dict(usuarios.carregar().get(id_evento, {}), id=id_evento)

    @pyqtSlot(str, str, result="QVariantMap")
    @protegido({})
    def excluirUsuario(self, id_evento, senha):
        """Remove alguém do cadastro. `{"ok": True}`, ou `{"erro": ...}` com
        "senha_incorreta" ou "nao_encontrado".

        Pede a senha como as outras duas, embora o pedido original fosse só
        para cadastrar e editar: remover é a mais destrutiva das três, e
        deixá-la como a única a passar pelo destrave de sessão faria da ação
        mais grave a menos protegida.

        Devolve mapa, e não o bool de antes, porque agora há dois motivos
        distintos de recusa e a tela precisa dizer qual foi."""
        if not self._autorizar_escrita(senha, "excluir_usuario"):
            return {"erro": "senha_incorreta"}

        registro = usuarios.carregar().get(id_evento)
        if registro is None:
            return {"erro": "nao_encontrado"}

        quando = usuarios.apagar(id_evento)
        rede.publicarEvento(_EVENTO_USUARIO_APAGADO, {
            "id": id_evento,
            "nome": registro.get("nome", ""),
            "quando": quando,
        })
        return {"ok": True}

    def _publicar_usuario(self, id_evento):
        """Anuncia à malha o cadastro/edição nascido nesta máquina. O id e a
        revisão viajam junto para que todas as máquinas gravem a MESMA marca
        para esta pessoa — mesmo cuidado de
        FechamentoController.registrarExtraDiaria."""
        registro = usuarios.carregar().get(id_evento)
        if not registro:
            return

        rede.publicarEvento(_EVENTO_USUARIO_ALTERADO, {
            "id": id_evento,
            "codigo": registro.get("codigo", ""),
            "nome": registro.get("nome", ""),
            "dataHora": registro.get("dataHora", ""),
            "idEventoRevisao": registro.get("idEventoRevisao", id_evento),
        })

    # ---------- Senha do dono: sincronização ----------

    def _aplicar_senha_reconciliacao(self, _chave, payload):
        self._registrar_senha_aprendida(payload or {})

    def _ao_receber_senha_remota(self, payload):
        """Reação ao gossip "senha_dono_alterada" — para uma senha definida
        ou trocada em outra máquina valer aqui na hora, sem esperar o próximo
        ciclo de reconciliação. O que chega é o hash, nunca a senha."""
        self._registrar_senha_aprendida(payload or {})

    def _registrar_senha_aprendida(self, payload):
        """Grava a senha aprendida de fora, venha ela do gossip ou da
        reconciliação. Idempotente por idEvento (ver senhaDono.aplicar_remoto):
        a mesma novidade chega pelos dois caminhos.

        Aplicar TRANCA esta sessão, mesmo que ela estivesse destravada: quem
        destravou aqui usou a senha ANTIGA, e a nova é justamente o jeito de o
        dono revogar o acesso de quem ficou com a anterior. Deixar a sessão
        aberta faria a troca de senha não valer para a única máquina onde ela
        mais precisa valer — a que está destravada agora."""
        if not senhaDono.aplicar_remoto(payload):
            return

        self._destravado_ate = 0.0
        self.senhaDonoAtualizada.emit()

    # ---------- Senha do dono: a tranca do cadastro ----------

    def _destrancado(self):
        return time.monotonic() < self._destravado_ate

    def _autorizar_escrita(self, senha, acao):
        """Confere a senha do dono para UMA gravação. Cada cadastro, cada
        edição e cada remoção pede a senha de novo.

        POR QUE POR AÇÃO, E NÃO POR SESSÃO. O destrave da tela continua
        existindo, mas ele agora só abre a VISTA do cadastro — quem entrou não
        ganha com isso o direito de gravar. Um destrave de cinco minutos
        significava que uma tela deixada aberta era uma janela de cinco minutos
        para cadastrar um usuário novo, e um usuário novo é um código que
        apaga comandas. Cadastrar alguém no cadastro que guarda as chaves da
        casa é a ação que menos pode andar por inércia.

        Enquanto NÃO houver senha nenhuma a gravação passa — mesmo bootstrap de
        usuarios.existe_algum: uma instalação nova não pode se trancar fora do
        próprio cadastro antes de o dono ter tido como definir a senha. A tela
        pede para defini-la logo na primeira abertura, e a liberação fica
        registrada no histórico, então a porta aberta nunca é silenciosa."""
        if not senhaDono.definida():
            historicoEventos.registrar_local("usuarios_sem_senha", {"acao": acao})
            return True

        if senhaDono.conferir(senha):
            return True

        historicoEventos.registrar_local("usuarios_senha_recusada", {"acao": acao})
        print(f"[UsuariosController] '{acao}' recusado: senha do dono incorreta.")
        return False

    @pyqtSlot(result=bool)
    @protegido(False)
    def senhaDonoDefinida(self):
        """Se já existe senha do dono. A tela usa para escolher entre pedir a
        senha e pedir para DEFINIR uma."""
        return senhaDono.definida()

    @pyqtSlot(result=bool)
    @protegido(False)
    def cadastroDestrancado(self):
        """Se a sessão pode VER o cadastro agora — a lista de nomes e a ficha
        de cada um, onde aparece o código de dois dígitos.

        Ver e gravar são coisas separadas desde que a senha passou a ser pedida
        por ação: isto aqui abre a vista, e cada gravação pede a senha de novo
        (ver _autorizar_escrita). Consultado pela tela a cada ação, e não
        guardado nela: o destrave expira sozinho, e uma cópia na QML ficaria
        dizendo "aberto" depois de o prazo ter passado."""
        return not senhaDono.definida() or self._destrancado()

    @pyqtSlot(str, result="QVariantMap")
    @protegido({})
    def destrancarCadastro(self, senha):
        """Confere a senha e, se ela bater, destrava a sessão por
        _DURACAO_DESTRAVE_SEGUNDOS. Confere E audita numa chamada só, pelo
        mesmo motivo de validarCodigo: separadas, seria possível uma tela
        conferir e esquecer de registrar.

        Devolve `{"destrancado": True}` ou
        `{"destrancado": False, "erro": "senha_incorreta" | "sem_senha"}`."""
        if not senhaDono.definida():
            # Nada a destrancar: sem senha o cadastro já está aberto. A tela
            # não deveria chegar aqui, e a resposta diz o que fazer em vez de
            # mentir um "destrancado" que nenhuma senha sustentou.
            return {"destrancado": False, "erro": "sem_senha"}

        if not senhaDono.conferir(senha):
            historicoEventos.registrar_local("usuarios_senha_recusada", {})
            return {"destrancado": False, "erro": "senha_incorreta"}

        self._destravado_ate = time.monotonic() + _DURACAO_DESTRAVE_SEGUNDOS
        historicoEventos.registrar_local("usuarios_destrancado", {})
        return {"destrancado": True}

    @pyqtSlot()
    @protegido(None)
    def trancarCadastro(self):
        """Tranca na hora, sem esperar o prazo. Chamado quando a tela de
        Usuários sai de vista — sair da tela é o sinal mais claro de que o
        dono terminou, e esperar os cinco minutos deixaria a próxima pessoa
        que abrisse a tela entrar sem senha."""
        self._destravado_ate = 0.0

    @pyqtSlot(str, str, result="QVariantMap")
    @protegido({})
    def definirSenhaDono(self, senha_atual, senha_nova):
        """Define a senha (primeira vez) ou troca a existente, e já deixa a
        sessão destravada — quem acabou de provar que sabe a senha não precisa
        digitá-la de novo na tela seguinte.

        Trocar EXIGE a senha atual, mesmo com a sessão destravada: o destrave
        dura cinco minutos e a tela pode ter ficado aberta: sem esta segunda
        checagem, passar por ali no minuto errado bastaria para tomar o
        cadastro do dono trocando a senha por outra.

        Erros possíveis: "senha_curta" (ver senhaDono.TAMANHO_MINIMO) e
        "senha_atual_incorreta"."""
        if senhaDono.definida() and not senhaDono.conferir(senha_atual):
            historicoEventos.registrar_local("usuarios_senha_recusada", {})
            return {"ok": False, "erro": "senha_atual_incorreta"}

        erro = senhaDono.validar(senha_nova)
        if erro:
            return {"ok": False, "erro": erro, "tamanhoMinimo": senhaDono.TAMANHO_MINIMO}

        data_hora = datetime.now().strftime("%d/%m/%Y %H:%M:%S")
        if senhaDono.definir(senha_nova, data_hora) is None:
            return {"ok": False, "erro": "senha_curta", "tamanhoMinimo": senhaDono.TAMANHO_MINIMO}

        self._destravado_ate = time.monotonic() + _DURACAO_DESTRAVE_SEGUNDOS

        registro = senhaDono.obter(senhaDono.CHAVE)
        if registro:
            rede.publicarEvento(_EVENTO_SENHA_DONO_ALTERADA, registro)
        return {"ok": True}

    # ---------- O guarda ----------

    @pyqtSlot(str, str, str, result="QVariantMap")
    @protegido({})
    def validarCodigo(self, codigo, acao, alvo):
        """Confere o código digitado e, no mesmo passo, registra a tentativa
        no histórico da malha. Valida E audita numa chamada só de propósito:
        separadas, seria possível uma tela liberar a ação e esquecer de
        registrar quem foi — e um guarda sem trilha não serve para nada.

        Devolve:
        - `{"autorizado": True, "id", "nome", "codigo"}` — liberado.
        - `{"autorizado": True, "semCadastro": True}` — ninguém cadastrado
          ainda; ver o bootstrap descrito em usuarios.existe_algum.
        - `{"autorizado": False, "erro": "codigo_invalido"}` — não existe.
        - `{"autorizado": False, "erro": "codigo_ambiguo", "candidatos": [...]}`
          — duas pessoas com o mesmo código; quem chamou pergunta qual
          (ver PopupAutorizacao) e volta por `autorizarComo`.
        """
        acao = acao or ""
        alvo = alvo or ""

        if not usuarios.existe_algum():
            historicoEventos.registrar_local("autorizacao_sem_cadastro", {"acao": acao, "alvo": alvo})
            return {"autorizado": True, "semCadastro": True, "nome": ""}

        candidatos = usuarios.por_codigo(codigo)
        if not candidatos:
            historicoEventos.registrar_local("autorizacao_negada", {
                "codigo": usuarios.normalizar_codigo(codigo) or str(codigo or ""),
                "acao": acao,
                "alvo": alvo,
            })
            return {"autorizado": False, "erro": "codigo_invalido"}

        if len(candidatos) > 1:
            # Não escolhe por conta própria: registrar a ação no nome da
            # pessoa errada é exatamente o dano que este guarda existe para
            # evitar. Quem chamou pergunta qual dos dois é.
            return {"autorizado": False, "erro": "codigo_ambiguo", "candidatos": candidatos}

        return self.autorizarComo(candidatos[0]["id"], acao, alvo)

    @pyqtSlot(str, str, str, result="QVariantMap")
    @protegido({})
    def autorizarComo(self, id_usuario, acao, alvo):
        """Libera em nome de um usuário já identificado e grava a linha de
        auditoria. Caminho normal de validarCodigo, e também o caminho de
        volta do desempate quando duas pessoas usam o mesmo código."""
        registro = usuarios.carregar().get(id_usuario)
        if registro is None:
            return {"autorizado": False, "erro": "nao_encontrado"}

        # registrar_local, e não publicarEvento: é uma linha por ação
        # protegida, e transformar isso em gossip poria tráfego constante na
        # malha para dizer o que a reconciliação do domínio "historico" (ver
        # redeService.py, registrado com historicoEventos.resumo/obter/aplicar)
        # entrega sozinha alguns segundos depois.
        historicoEventos.registrar_local("autorizacao_concedida", {
            "usuario": registro.get("nome", ""),
            "id": id_usuario,
            "acao": acao or "",
            "alvo": alvo or "",
        })
        return {
            "autorizado": True,
            "id": id_usuario,
            "nome": registro.get("nome", ""),
            "codigo": registro.get("codigo", ""),
        }
