#!/bin/bash

if [ "$SSL_ENABLE" ]; then
  if [ "$SSL_ENABLE" == "server" ]; then
    echo "$SERVER_PRIVATE_KEY" > /etc/server.pem
    echo "$CLIENT_PUBLIC_KEY" > /etc/client.crt
    chmod 600 /etc/server.pem /etc/client.crt
  else
    echo "$CLIENT_PRIVATE_KEY" > /etc/client.pem
    echo "$SERVER_PUBLIC_KEY" > /etc/server.crt
    chmod 600 /etc/client.pem /etc/server.crt
  fi
fi

env | grep _TCP= | while read line; do
  name=$(echo $line | sed -e 's/.*_PORT_\([0-9]*\)_TCP=tcp:\/\/\(.*\):\(.*\)/socat_\1/')

  if [ -z "$SSL_ENABLE" ]; then
    cmd=$(echo $line | sed -e 's/.*_PORT_\([0-9]*\)_TCP=tcp:\/\/\(.*\):\(.*\)/socat -ls TCP4-LISTEN:\1,fork,reuseaddr TCP4:\2:\3 /')
  else
    if [ "$SSL_ENABLE" == "server" ]; then
      cmd=$(echo $line | sed -e 's/.*_PORT_\([0-9]*\)_TCP=tcp:\/\/\(.*\):\(.*\)/socat OPENSSL-LISTEN:\1,fork,reuseaddr,cert=\/etc\/server.pem,cafile=\/etc\/client.crt TCP4:\2:\3 /')
    else
      cmd=$(echo $line | sed -e 's/.*_PORT_\([0-9]*\)_TCP=tcp:\/\/\(.*\):\(.*\)/socat TCP-LISTEN:\1,reuseaddr,fork OPENSSL:\2:\3,cert=\/etc\/client.pem,cafile=\/etc\/server.crt /')
    fi
  fi

  cat <<EOF >> /etc/supervisor.d/socat.ini
[program:$name]
command=$cmd
numprocs=1
autostart=true
autorestart=true
EOF
done

exec supervisord -n