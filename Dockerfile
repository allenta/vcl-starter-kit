FROM ubuntu:resolute-20260421

ENV VARNISH_VERSION=6.0.17r3-1~resolute
ENV GO_VERSION=1.26.1

ENV PATH=$PATH:/usr/local/go/bin

ENV DEBIAN_FRONTEND=noninteractive

RUN groupadd -g 5000 dev \
    && useradd -u 5000 -g 5000 -m -s /bin/bash dev

RUN apt update \
    && apt install -y \
        apt-transport-https \
        bindfs \
        binutils \
        curl \
        gpg \
        less \
        nano \
        pkg-config \
    && apt clean \
    && rm -rf /var/lib/apt/lists/*

RUN curl -L -s https://packagecloud.io/install/repositories/varnishplus/60-enterprise/script.deb.sh | bash \
    && apt update \
    && apt install -y \
        varnish-plus=${VARNISH_VERSION} \
        varnish-plus-dev=${VARNISH_VERSION} \
        varnish-plus-ha=${VARNISH_VERSION} \
        varnish-plus-vmods-extra=${VARNISH_VERSION} \
    && apt clean \
    && rm -rf /var/lib/apt/lists/*

RUN curl -L -s https://go.dev/dl/go${GO_VERSION}.linux-$(dpkg --print-architecture).tar.gz | tar xvfz - -C /usr/local

COPY ./docker-entrypoint.sh /
ENTRYPOINT ["/docker-entrypoint.sh"]
