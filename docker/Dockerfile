# Imagem só para TESTAR a malha de rede local (services/redeService.py) com
# várias "máquinas" de verdade (containers em namespaces de rede separados,
# na mesma rede Docker) — não é para rodar o sistema em produção.
#
# Roda a interface em modo offscreen (sem servidor X): não dá pra ver a
# janela, mas todo o resto (salvar pedido, descoberta UDP, malha TCP,
# sincronização) é o código de verdade, sem nenhuma adaptação.
FROM python:3.14-slim

# Bibliotecas de sistema exigidas pelo Qt6/PyQt6 mesmo em modo offscreen
# (renderização de fontes, xcb, dbus etc.) — sem elas o import do PyQt6 falha.
RUN apt-get update && apt-get install -y --no-install-recommends \
        libgl1 \
        libegl1 \
        libxkbcommon0 \
        libfontconfig1 \
        libfreetype6 \
        libdbus-1-3 \
        libxcb-cursor0 \
        libxcb-icccm4 \
        libxcb-image0 \
        libxcb-keysyms1 \
        libxcb-randr0 \
        libxcb-render-util0 \
        libxcb-shape0 \
        libxcb-xinerama0 \
        libxcb1 \
        libx11-6 \
        libglib2.0-0 \
        libgssapi-krb5-2 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Instala o PyQt6 no build da imagem — preConfig.garantir_dependencias() só
# confirma que já está instalado e não tenta baixar nada em runtime.
RUN pip install --no-cache-dir PyQt6

COPY . /app

ENV QT_QPA_PLATFORM=offscreen
ENV PYTHONUNBUFFERED=1

CMD ["python3", "main.py"]
