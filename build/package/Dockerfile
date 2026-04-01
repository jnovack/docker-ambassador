FROM alpine:3.21
LABEL maintainer="Justin J. Novack <jnovack@gmail.com>"

ENTRYPOINT ["/usr/bin/entrypoint.sh"]

RUN apk add --update --no-cache openssl socat supervisor && \
    rm -rf /var/cache/apk

COPY rootfs/entrypoint.sh /usr/bin/entrypoint.sh
