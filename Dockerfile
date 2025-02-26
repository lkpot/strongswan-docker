FROM debian:bookworm-slim AS source

ENV VERSION=6.0.0 \
    CHECKSUM=028c23911cbd8f87922a331b7750012b86ef7e4609894b57e7550214714952a1

WORKDIR /source
ADD --checksum="sha256:${CHECKSUM}" "https://github.com/strongswan/strongswan/releases/download/${VERSION}/strongswan-${VERSION}.tar.gz" .

RUN tar -xf "strongswan-${VERSION}.tar.gz" -C . --strip-components=1 && \
    rm "strongswan-${VERSION}.tar.gz"

FROM debian:bookworm-slim AS build

ENV INSTALLDIR=/install

# Place all configuration files into a seperate directory
# This allows us to use a single mounting point at runtime
ENV SYSCONFDIR=/etc/strongswan

RUN apt-get update && \
    apt-get install -y \
      build-essential \
      libcap-dev \
      libcap2-bin \
      libssl-dev && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /build
COPY --from=source /source .

RUN ./configure \
      --prefix=/usr \
      --sysconfdir=${SYSCONFDIR} \
      --disable-defaults \
      --enable-silent-rules \
      --enable-charon \
      --enable-ikev2 \
      --enable-vici \
      --enable-swanctl \
      --enable-nonce \
      --enable-random \
      --enable-drbg \
      --enable-openssl \
      --enable-pem \
      --enable-x509 \
      --enable-constraints \
      --enable-pki \
      --enable-pubkey \
      --enable-socket-default \
      --enable-kernel-netlink \
      --enable-resolve \
      --enable-eap-identity \
      --enable-eap-tls \
      --enable-updown \
      --with-capabilities=libcap \
      --with-piddir=/var/run/strongswan && \
    make -j "$(nproc)" all && \
    make install DESTDIR=${INSTALLDIR}

# Set capabilities to run charon rootless
RUN setcap 'cap_net_admin,cap_net_bind_service=+eip' ${INSTALLDIR}/usr/libexec/ipsec/charon

# Create symlink for charon
RUN ln -sf /usr/libexec/ipsec/charon ${INSTALLDIR}/usr/bin/charon

# Copy configuration files
COPY strongswan.conf ${INSTALLDIR}${SYSCONFDIR}
COPY strongswan.d ${INSTALLDIR}${SYSCONFDIR}/strongswan.d

FROM debian:bookworm-slim

COPY --from=build /install /

RUN apt-get update && \
    apt-get install -y iptables libcap2-bin libssl3 && \
    # Set capabilities to run iptables rootless
    setcap 'cap_net_admin=+ep' "$(realpath /usr/sbin/iptables)" && \
    apt-get purge -y libcap2-bin && \
    rm -rf /var/lib/apt/lists/* && \
    useradd --system strongswan && \
    # strongswan piddir must be writeable for any user that might
    # get mapped into the container
    mkdir -p /var/run/strongswan && chmod 0777 /var/run/strongswan

USER strongswan

EXPOSE 500/udp
EXPOSE 4500/udp

CMD [ "charon" ]
