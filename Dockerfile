FROM alpine:3.23

ARG WSTUNNEL_VERSION=10.5.5
ARG TARGETARCH

RUN apk add --no-cache ca-certificates tar tzdata && \
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
    rm /tmp/wstunnel.tar.gz

EXPOSE 8080

ENTRYPOINT ["wstunnel"]
