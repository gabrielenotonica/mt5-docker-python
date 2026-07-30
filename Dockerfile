# mt5-docker-silicon — MetaTrader 5 headless in Docker + Python rpyc bridge.
# Runs on Apple Silicon / arm64 hosts via an x86_64 QEMU VM (Colima); see README.
#
# Inspired by gmag11/MetaTrader5-Docker (MIT). Differences: every runtime
# dependency is PINNED (the upstream image breaks when mt5linux/numpy float to
# incompatible versions), and the flaky `mt5linux` server is replaced by a tiny
# self-contained rpyc `SlaveService` (see Metatrader/server.py) — no CLI drift.
FROM ghcr.io/linuxserver/baseimage-kasmvnc:debianbookworm

ARG BUILD_DATE
ARG VERSION
LABEL build_version="mt5-docker-silicon ${VERSION} build ${BUILD_DATE}"
LABEL maintainer="Apeyron"

ENV TITLE=MetaTrader5
ENV WINEPREFIX="/config/.wine"
ENV WINEDEBUG=-all

# wine (stable channel) + curl/python3 for the healthcheck. The wine PREFIX lives
# in the /config volume, so the Windows Python + MT5 + pip deps are installed at
# first boot by start.sh (a volume is empty at build time) — but PINNED there.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        python3 python3-pip wget curl gnupg2 software-properties-common ca-certificates iproute2 \
    && mkdir -pm755 /etc/apt/keyrings \
    && wget -O /etc/apt/keyrings/winehq-archive.key https://dl.winehq.org/wine-builds/winehq.key \
    && wget -NP /etc/apt/sources.list.d/ https://dl.winehq.org/wine-builds/debian/dists/bookworm/winehq-bookworm.sources \
    && dpkg --add-architecture i386 \
    && apt-get update \
    # Wine PINNED to 10.0 on purpose. Wine 11.0 (current winehq-stable) makes the
    # MetaTrader5 installer abort with "A debugger has been found running in your
    # system" — a MetaQuotes anti-debug false-positive that regressed on Wine 11.
    # Verified: 10.0 installs MT5 cleanly under the same QEMU VM, 11.0 does not.
    && apt-get install --install-recommends -y \
        winehq-stable=10.0.0.0~bookworm-1 \
        wine-stable=10.0.0.0~bookworm-1 \
        wine-stable-amd64=10.0.0.0~bookworm-1 \
        wine-stable-i386=10.0.0.0~bookworm-1 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /etc/apt/keyrings/winehq-archive.key

COPY /Metatrader /Metatrader
RUN chmod +x /Metatrader/start.sh
COPY /root /

EXPOSE 3000 8001
VOLUME /config
