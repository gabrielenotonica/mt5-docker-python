# mt5-docker-python — MetaTrader 5, headless, with a Python bridge.
#
# The image is x86_64: MetaTrader 5 is a Windows x86 program and runs under Wine.
# On Apple Silicon it still works, but only inside an x86_64 VM with 4 KB pages
# (Colima) — see the README for why arm64 alone is not enough.
#
# Only the OS-level pieces are baked in here. MetaTrader 5, the Windows Python
# and the pinned wheels are installed on first boot into the /config volume,
# because a volume is empty at build time; mt5/entrypoint.sh owns that step and
# holds the version pins.

FROM ghcr.io/linuxserver/baseimage-kasmvnc:debianbookworm

ARG BUILD_DATE
ARG VERSION
LABEL maintainer="Gabriele Notonica"
LABEL org.opencontainers.image.source="https://github.com/gabrielenotonica/mt5-docker-python"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.description="MetaTrader 5 headless in Docker with a Python bridge, runnable on Apple Silicon"
LABEL build_version="mt5-docker-python ${VERSION} build ${BUILD_DATE}"

ENV TITLE=MetaTrader5
ENV WINEPREFIX=/config/.wine
ENV WINEDEBUG=-all

# Wine is pinned to 10.0 deliberately. On Wine 11.0 the MetaTrader 5 installer
# aborts with "A debugger has been found running in your system" — an anti-debug
# false positive that 10.0 does not trigger. Verified both ways in the same VM.
ARG WINE_VERSION=10.0.0.0~bookworm-1

# Base tooling: curl for the first-boot downloads, iproute2 for the healthcheck,
# gnupg/wget to add the WineHQ repository below.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        gnupg2 \
        iproute2 \
        python3 \
        python3-pip \
        software-properties-common \
        wget \
    && rm -rf /var/lib/apt/lists/*

# WineHQ's own repository — Debian's Wine is too old for the terminal.
RUN mkdir -pm755 /etc/apt/keyrings \
    && wget -O /etc/apt/keyrings/winehq-archive.key https://dl.winehq.org/wine-builds/winehq.key \
    && wget -NP /etc/apt/sources.list.d/ https://dl.winehq.org/wine-builds/debian/dists/bookworm/winehq-bookworm.sources \
    && dpkg --add-architecture i386 \
    && apt-get update \
    && apt-get install --install-recommends -y \
        "winehq-stable=${WINE_VERSION}" \
        "wine-stable=${WINE_VERSION}" \
        "wine-stable-amd64=${WINE_VERSION}" \
        "wine-stable-i386=${WINE_VERSION}" \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /etc/apt/keyrings/winehq-archive.key

COPY mt5 /mt5
RUN chmod +x /mt5/entrypoint.sh

# Drops root/defaults/autostart into place, which is what launches the entrypoint
# inside the graphical session.
COPY root/ /

EXPOSE 3000 8001
VOLUME /config
