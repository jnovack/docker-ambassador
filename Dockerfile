FROM alpine:latest

RUN apk update && \
    apk add --no-cache openssl socat supervisor

ADD /run.sh /run.sh
RUN mkdir /etc/supervisor.d/ && \
    chmod 755 /run.sh

CMD ["sh", "/run.sh"]