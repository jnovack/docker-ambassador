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
    cmd=$(echo $line | sed -e 's/.*_PORT_\([0-9]*\)_TCP=tcp:\/\/\(.*\):\(.*\)/socat -ls -d -d -ls TCP4-LISTEN:\1,fork,reuseaddr TCP4:\2:\3 /')
  else
    if [ "$SSL_ENABLE" == "server" ]; then
      cmd=$(echo $line | sed -e 's/.*_PORT_\([0-9]*\)_TCP=tcp:\/\/\(.*\):\(.*\)/socat -ls -d -d OPENSSL-LISTEN:\1,fork,reuseaddr,cert=\/etc\/server.pem,cafile=\/etc\/client.crt TCP4:\2:\3 /')
    else
      cmd=$(echo $line | sed -e 's/.*_PORT_\([0-9]*\)_TCP=tcp:\/\/\(.*\):\(.*\)/socat -ls -d -d TCP-LISTEN:\1,reuseaddr,fork OPENSSL:\2:\3,cert=\/etc\/client.pem,cafile=\/etc\/server.crt,verify=0 /')
    fi
  fi

  cat <<EOF >> /etc/supervisor.d/socat.ini
[program:$name]
command=$cmd
numprocs=1
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
autostart=true
autorestart=true
EOF
done

echo
echo "/etc/hosts"
echo "---------------------------"
cat /etc/hosts

echo
echo "/etc/supervisor.d/socat.ini"
echo "---------------------------"
cat /etc/supervisor.d/socat.ini

echo
exec supervisord -n -c /etc/supervisord.conf