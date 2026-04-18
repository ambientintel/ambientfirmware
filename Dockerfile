# syntax=docker/dockerfile:1
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=en_US.UTF-8

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        build-essential \
        git \
        python3 \
        python3-pip \
        python3-pexpect \
        chrpath \
        diffstat \
        gawk \
        texinfo \
        wget \
        curl \
        sudo \
        bc \
        bison \
        flex \
        libssl-dev \
        libncurses-dev \
        cpio \
        zstd \
        lz4 \
        file \
        locales \
        unzip \
        xz-utils \
        rsync \
        device-tree-compiler \
        u-boot-tools \
        libsdl1.2-dev \
        xterm \
        zip && \
    rm -rf /var/lib/apt/lists/*

RUN locale-gen en_US.UTF-8

ARG USER_ID=1000
ARG GROUP_ID=1000
RUN set -eux; \
    if ! getent group ${GROUP_ID} >/dev/null; then \
        groupadd -g ${GROUP_ID} dev; \
    fi; \
    if ! getent passwd ${USER_ID} >/dev/null; then \
        useradd -u ${USER_ID} -g ${GROUP_ID} -m -s /bin/bash dev; \
    fi; \
    echo "dev ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

USER dev
WORKDIR /workspace

CMD ["/bin/bash"]
