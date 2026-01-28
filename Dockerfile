FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

# Настройка DNS для решения проблем с разрешением имен
RUN echo "nameserver 8.8.8.8" > /etc/resolv.conf && \
    echo "nameserver 8.8.4.4" >> /etc/resolv.conf

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      wget \
      ca-certificates \
      xz-utils \
      locales \
      mesa-utils \
      libgl1 \
      libegl1 \
      libgbm1 \
      libglu1-mesa \
      libglib2.0-0 \
      libnss3 \
      libxss1 \
      libasound2 \
      libpulse0 \
      libxkbcommon0 \
      libxkbcommon-x11-0 \
      libatk1.0-0 \
      libatk-bridge2.0-0 \
      libgtk-3-0 \
      libdbus-1-3 \
      libxcb1 \
      libxrandr2 \
      libxrender1 \
      libxcomposite1 \
      libxcursor1 \
      libxdamage1 \
      libxi6 \
      libxtst6 \
      libfontconfig1 \
      libfreetype6 && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /opt

# Download and extract Telegram Desktop (official tar.xz contains a single "Telegram" dir)
RUN wget -O tdesktop.tar.xz https://telegram.org/dl/desktop/linux && \
    tar -xJf tdesktop.tar.xz && \
    rm tdesktop.tar.xz

# Create TelegramForcePortable directory and tdata within it
RUN mkdir -p /opt/Telegram/TelegramForcePortable/tdata

ENV QT_X11_NO_MITSHM=1 \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8
WORKDIR /opt/Telegram

ENTRYPOINT ["./Telegram"]


