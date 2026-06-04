FROM alpine:3.23

ARG WSTUNNEL_VERSION=10.5.5
ARG TARGETARCH

RUN apk add --no-cache ca-certificates tar openssh-server && \
    case "${TARGETARCH}" in \
      amd64) ARCH="amd64" ;; \
      arm64) ARCH="arm64" ;; \
      arm)   ARCH="armv7" ;; \
      *) echo "Unsupported arch: ${TARGETARCH}" && exit 1 ;; \
    esac && \
    wget -qO /tmp/wstunnel.tar.gz \
      "https://github.com/erebe/wstunnel/releases/download/v${WSTUNNEL_VERSION}/wstunnel_${WSTUNNEL_VERSION}_linux_${ARCH}.tar.gz" && \
    tar -xzf /tmp/wstunnel.tar.gz -C /usr/local/bin wstunnel && \
    chmod +x /usr/local/bin/wstunnel && \
    rm /tmp/wstunnel.tar.gz && \
    adduser -D -u 1000 -s /sbin/nologin jumpuser && \
    passwd -d jumpuser && \
    mkdir -p /home/jumpuser/.ssh && \
    chmod 700 /home/jumpuser/.ssh && \
    chown jumpuser:jumpuser /home/jumpuser/.ssh

COPY sshd_config /etc/ssh/sshd_config
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 8080

ENTRYPOINT ["/entrypoint.sh"]
