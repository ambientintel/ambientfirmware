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
        python3-dev \
        python3-setuptools \
        python3-yaml \
        python3-pyelftools \
        python3-jsonschema \
        python3-lxml \
        swig \
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
        libgnutls28-dev \
        libftdi-dev \
        libusb-1.0-0-dev \
        libcap-dev \
        libpython3-dev \
        uuid-dev \
        pkg-config \
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

# yamllint is not packaged for Ubuntu 22.04 — pip required
RUN pip3 install yamllint

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