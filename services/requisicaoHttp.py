"""HTTPS para as APIs de mapa (Photon, ipinfo, Overpass, ViaCEP) feito só com
o Python — sem passar por nada do Windows que possa barrar ou travar a
requisição.

POR QUE EXISTE. As sugestões de endereço iam pelo QNetworkAccessManager do Qt,
que no Windows negocia o HTTPS pelo schannel (o TLS do próprio sistema),
consulta o proxy do sistema (inclusive a detecção automática, WPAD) e valida o
certificado pela lista de raízes do Windows. Nas máquinas Windows da pizzaria a
requisição ao Photon nunca terminava — nem pelo timeout —, e o botão "Definir"
da tela Rede ficava em "Buscando..." para sempre.

Aqui cada uma dessas peças é trocada pela do Python:

- o TLS é o OpenSSL que vem embutido no Python (o módulo `ssl`), e não o
  schannel;
- os certificados raiz vêm do certifi (a lista da Mozilla), e não da lista do
  Windows — que, numa máquina sem atualização, não conhece as raízes novas da
  Let's Encrypt usadas pelo Photon e pelo Overpass. Sem o certifi instalado,
  fica a lista padrão do `ssl`;
- o proxy é ignorado (ProxyHandler vazio): o urllib, sozinho, também leria o
  proxy do registro do Windows.

O que nenhuma biblioteca contorna: um firewall ou antivírus que bloqueie o
python.exe inteiro de sair para a internet.

É bloqueante — chame numa thread (ver SugestoesEnderecoService._pedir_json e
services/montadorIndiceRuas.py)."""

import json
import ssl
import urllib.error
import urllib.parse
import urllib.request

try:
    import certifi
except ImportError:  # dependência nova: a máquina pode ainda não ter instalado
    certifi = None

# A política de uso do Photon pede um User-Agent que identifique a aplicação.
USER_AGENT = "ppgs-system"


class ErroRequisicao(Exception):
    """Falha de rede, de TLS, de HTTP ou de JSON. `status` é o código HTTP
    quando o servidor chegou a responder, e 0 nos outros casos."""

    def __init__(self, mensagem, status=0):
        super().__init__(mensagem)
        self.status = status


def _montar_abridor():
    if certifi is not None:
        contexto = ssl.create_default_context(cafile=certifi.where())
    else:
        contexto = ssl.create_default_context()
    return urllib.request.build_opener(
        urllib.request.ProxyHandler({}),
        urllib.request.HTTPSHandler(context=contexto),
    )


# Montado uma vez só: ler a lista de certificados custa alguns milissegundos,
# e o mesmo abridor serve às várias threads que fazem requisição.
_abridor = _montar_abridor()


def obter_json(url, parametros=None, formulario=None, timeout=10):
    """O JSON decodificado da resposta.

    `parametros` vai na query string — dict ou lista de pares, e a lista é o
    que permite repetir a chave (o `layer` do Photon). `formulario`, quando
    dado, vira o corpo de um POST. `timeout` vale para cada espera de rede
    (conectar, cada leitura), e não para a requisição inteira.

    Levanta ErroRequisicao em qualquer falha."""
    if parametros:
        url = f"{url}?{urllib.parse.urlencode(parametros)}"
    corpo = urllib.parse.urlencode(formulario).encode("utf-8") if formulario is not None else None
    requisicao = urllib.request.Request(url, data=corpo, headers={"User-Agent": USER_AGENT})
    try:
        with _abridor.open(requisicao, timeout=timeout) as resposta:
            return json.load(resposta)
    except urllib.error.HTTPError as erro:
        raise ErroRequisicao(f"HTTP {erro.code}", erro.code) from erro
    except (urllib.error.URLError, OSError, ValueError) as erro:
        raise ErroRequisicao(str(getattr(erro, "reason", None) or erro)) from erro
