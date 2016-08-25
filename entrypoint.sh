#!/bin/sh

if [ "$SSL" ]; then
  if [ "$SSL" == "server" ]; then
    if [ "$SERVER_PRIVATE_KEY" ]; then
      echo "$SERVER_PRIVATE_KEY" > /etc/server.pem
    else
      echo "[WARN] Generating new keys..."
      openssl req -nodes -new -x509 -keyout /etc/server.key -out /etc/server.crt -subj "/C=NO/ST=None/L=None/O=Testing/OU=Server/CN=server.jnovack-ambassador.local/emailAddress=server@jnovack-ambassador.local" &> /dev/null
      cat /etc/server.key /etc/server.crt > /etc/server.pem
      rm /etc/server.key
    fi
    chmod 600 /etc/server.pem
    echo
    echo ":: server.crt ::"
    cat /etc/server.crt
  else
    if [ "$CLIENT_PRIVATE_KEY" ]; then
      echo "$CLIENT_PRIVATE_KEY" > /etc/client.pem
    else
      echo "[WARN] Generating new keys..."
      openssl req -nodes -new -x509 -keyout /etc/client.key -out /etc/client.crt -subj "/C=NO/ST=None/L=None/O=Testing/OU=Client/CN=client.jnovack-ambassador.local/emailAddress=client@jnovack-ambassador.local" &> /dev/null
      cat /etc/client.key /etc/client.crt > /etc/client.pem
      rm /etc/client.key
    fi
    chmod 600 /etc/client.pem
    echo
    echo ":: client.crt ::"
    cat /etc/client.crt
  fi
  echo
else
  echo "[WARN] SSL is NOT enabled"
fi

env | grep _TCP= | while read line; do
  name=$(echo $line | sed -e 's/.*_PORT_\([0-9]*\)_TCP=tcp:\/\/\(.*\):\(.*\)/socat_\1/')

  if [ -z "$SSL" ]; then
    echo "[INFO] Initiating socat socket..."
    cmd=$(echo $line | sed -e 's/.*_PORT_\([0-9]*\)_TCP=tcp:\/\/\(.*\):\(.*\)/socat -ls -d -d -ls TCP4-LISTEN:\1,fork,reuseaddr TCP4:\2:\3 /')
  else
    if [ "$SSL" == "server" ]; then
      echo "[INFO] Initiating socat server..."
      if [ -z "$CLIENT_PUBLIC_KEY" ]; then
        echo "[WARN] ...server is NOT verifying certificates"
        cmd=$(echo $line | sed -e 's/.*_PORT_\([0-9]*\)_TCP=tcp:\/\/\(.*\):\(.*\)/socat -ls -d -d OPENSSL-LISTEN:\1,fork,reuseaddr,cert=\/etc\/server.pem,verify=0 TCP4:\2:\3 /')
      else
        echo "$CLIENT_PUBLIC_KEY" > /etc/client.crt
        chmod 600 /etc/client.crt
        echo "[INFO] ...server is VERIFYING certificates"
        cmd=$(echo $line | sed -e 's/.*_PORT_\([0-9]*\)_TCP=tcp:\/\/\(.*\):\(.*\)/socat -ls -d -d OPENSSL-LISTEN:\1,fork,reuseaddr,cert=\/etc\/server.pem,cafile=\/etc\/client.crt,verify=1 TCP4:\2:\3 /')
      fi
    else
      echo "[INFO] Initiating socat client..."
      if [ -z "$SERVER_PUBLIC_KEY" ]; then
        echo "[WARN] ...client is NOT verifying certificates"
        cmd=$(echo $line | sed -e 's/.*_PORT_\([0-9]*\)_TCP=tcp:\/\/\(.*\):\(.*\)/socat -ls -d -d TCP-LISTEN:\1,reuseaddr,fork OPENSSL:\2:\3,cert=\/etc\/client.pem,verify=0 /')
      else
        echo "$SERVER_PUBLIC_KEY" > /etc/server.crt
        chmod 600 /etc/server.crt
        echo "[INFO] ...client is VERIFYING certificates"
        cmd=$(echo $line | sed -e 's/.*_PORT_\([0-9]*\)_TCP=tcp:\/\/\(.*\):\(.*\)/socat -ls -d -d TCP-LISTEN:\1,reuseaddr,fork OPENSSL:\2:\3,cert=\/etc\/client.pem,cafile=\/etc\/server.crt,verify=1 /')
      fi
    fi
  fi

  mkdir /etc/supervisor.d/
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
echo ":: socat.ini ::"
echo "---------------"
cat /etc/supervisor.d/socat.ini

echo
exec supervisord -n -c /etc/supervisord.conf
