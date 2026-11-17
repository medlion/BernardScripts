FROM haproxytech/haproxy-debian:s6-latest

USER root

RUN chown -R haproxy:haproxy /usr/local/etc/haproxy

# HAProxy, the master socket and gopherd all create sockets/pidfile directly in
# /run (/var/run is a symlink to it), so the unprivileged haproxy user must own it.
RUN chown haproxy:haproxy /run

# Wildcard dev certificate signed by the host's mkcert CA (trusted by the host's browsers).
# The CA is mounted only for this step, so its private key is never stored in an image layer.
RUN curl -sfSL -o /usr/local/bin/mkcert \
      https://github.com/FiloSottile/mkcert/releases/download/v1.4.4/mkcert-v1.4.4-linux-amd64 \
 && chmod +x /usr/local/bin/mkcert

# Space-separated hostnames for the certificate. A wildcard like *.localhost is rejected by
# TLS clients (no wildcard directly under a single-label domain), so names are listed explicitly.
ARG CERT_NAMES="localhost"
RUN --mount=from=caroot,target=/caroot \
    mkdir -p /usr/local/etc/haproxy/ssl \
 && CAROOT=/caroot mkcert -cert-file /tmp/c.pem -key-file /tmp/k.pem $CERT_NAMES \
 && cat /tmp/c.pem /tmp/k.pem > /usr/local/etc/haproxy/ssl/wildcard.pem \
 && rm /tmp/c.pem /tmp/k.pem \
 && chown -R haproxy:haproxy /usr/local/etc/haproxy/ssl \
 && chmod 600 /usr/local/etc/haproxy/ssl/wildcard.pem

COPY dataplaneapi.yml /etc/haproxy/dataplaneapi.yml
COPY haproxy.cfg /etc/haproxy/haproxy.cfg

USER haproxy

