#!/bin/sh

# write_var VAR VAR_FILE OUTFILE
# Resolves the value of VAR or VAR_FILE and writes it to OUTFILE.
#   FATAL — if both VAR and VAR_FILE are set (no precedence, user error).
#   WARN  — if VAR (non-_FILE form) is used; advises using VAR_FILE instead.
#   NOOP  — if neither is set; OUTFILE is not created.
write_var() {
  eval "_wv_val=\"\$$1\"" "_wv_fval=\"\$$2\""
  if [ -n "$_wv_val" ] && [ -n "$_wv_fval" ]; then
    echo "[FATAL] Both $1 and $2 are set. Provide exactly one." >&2
    exit 1
  fi
  if [ -n "$_wv_val" ]; then
    echo "[WARN ] $1 is set as an environment variable. Prefer $2 with a path." >&2
    printf '%s\n' "$_wv_val" > "$3"
  elif [ -n "$_wv_fval" ]; then
    if ! cat "$_wv_fval" > "$3"; then
      echo "[FATAL] Cannot read $2: $_wv_fval" >&2
      exit 1
    fi
  fi
}

# is_provided VAR VAR_FILE — returns 0 if either is non-empty, 1 otherwise
is_provided() {
  eval "_ip_v=\"\$$1\"" "_ip_f=\"\$$2\""
  [ -n "$_ip_v" ] || [ -n "$_ip_f" ]
}

if [ "$SSL" ]; then
  if [ "$SSL" = "server" ]; then
    _key_set=0; _cert_set=0
    is_provided SERVER_PRIVATE_KEY SERVER_PRIVATE_KEY_FILE && _key_set=1
    is_provided SERVER_PUBLIC_CERT  SERVER_PUBLIC_CERT_FILE  && _cert_set=1

    if [ "$_key_set" = 1 ] || [ "$_cert_set" = 1 ]; then
      if [ "$_key_set" = 0 ]; then
        echo "[FATAL] SERVER_PUBLIC_CERT[_FILE] requires SERVER_PRIVATE_KEY[_FILE]." >&2; exit 1
      fi
      if [ "$_cert_set" = 0 ]; then
        echo "[FATAL] SERVER_PRIVATE_KEY[_FILE] requires SERVER_PUBLIC_CERT[_FILE]." >&2; exit 1
      fi
      write_var SERVER_PRIVATE_KEY SERVER_PRIVATE_KEY_FILE /tmp/server.key
      write_var SERVER_PUBLIC_CERT  SERVER_PUBLIC_CERT_FILE  /etc/server.crt
      cat /tmp/server.key /etc/server.crt > /etc/server.pem
      rm -f /tmp/server.key
    else
      echo "[WARN ] No server key/cert provided — generating a self-signed certificate."
      _cert_cn="${CERT_CN:-server.ambassador.local}"
      openssl req -nodes -new -x509 \
        -keyout /tmp/server.key -out /etc/server.crt \
        -subj "/C=NO/ST=None/L=None/O=Testing/OU=Server/CN=${_cert_cn}" \
        -addext "subjectAltName=DNS:${_cert_cn}" \
        2>/dev/null
      cat /tmp/server.key /etc/server.crt > /etc/server.pem
      rm -f /tmp/server.key
    fi
    chmod 600 /etc/server.pem
    echo ":: server.crt ::"
    cat /etc/server.crt

    # Optional: CA cert used to verify the connecting client (mutual auth)
    if is_provided CLIENT_PUBLIC_KEY CLIENT_PUBLIC_KEY_FILE; then
      write_var CLIENT_PUBLIC_KEY CLIENT_PUBLIC_KEY_FILE /etc/client.crt
      chmod 600 /etc/client.crt
    fi

  else
    _key_set=0; _cert_set=0
    is_provided CLIENT_PRIVATE_KEY CLIENT_PRIVATE_KEY_FILE && _key_set=1
    is_provided CLIENT_PUBLIC_CERT  CLIENT_PUBLIC_CERT_FILE  && _cert_set=1

    if [ "$_key_set" = 1 ] || [ "$_cert_set" = 1 ]; then
      if [ "$_key_set" = 0 ]; then
        echo "[FATAL] CLIENT_PUBLIC_CERT[_FILE] requires CLIENT_PRIVATE_KEY[_FILE]." >&2; exit 1
      fi
      if [ "$_cert_set" = 0 ]; then
        echo "[FATAL] CLIENT_PRIVATE_KEY[_FILE] requires CLIENT_PUBLIC_CERT[_FILE]." >&2; exit 1
      fi
      write_var CLIENT_PRIVATE_KEY CLIENT_PRIVATE_KEY_FILE /tmp/client.key
      write_var CLIENT_PUBLIC_CERT  CLIENT_PUBLIC_CERT_FILE  /etc/client.crt
      cat /tmp/client.key /etc/client.crt > /etc/client.pem
      rm -f /tmp/client.key
    else
      echo "[WARN ] No client key/cert provided — generating a self-signed certificate."
      _cert_cn="${CERT_CN:-client.ambassador.local}"
      openssl req -nodes -new -x509 \
        -keyout /tmp/client.key -out /etc/client.crt \
        -subj "/C=NO/ST=None/L=None/O=Testing/OU=Client/CN=${_cert_cn}" \
        -addext "subjectAltName=DNS:${_cert_cn}" \
        2>/dev/null
      cat /tmp/client.key /etc/client.crt > /etc/client.pem
      rm -f /tmp/client.key
    fi
    chmod 600 /etc/client.pem
    echo ":: client.crt ::"
    cat /etc/client.crt

    # Optional: CA cert used to verify the server (server auth)
    if is_provided SERVER_PUBLIC_KEY SERVER_PUBLIC_KEY_FILE; then
      write_var SERVER_PUBLIC_KEY SERVER_PUBLIC_KEY_FILE /etc/server.crt
      chmod 600 /etc/server.crt
    fi
  fi
else
  echo "[WARN ] SSL is NOT enabled"
fi

mkdir -p /etc/supervisor.d/
env | grep _TCP= | while read -r line; do
  name=$(echo "$line" | sed -e 's/.*_PORT_\([0-9]*\)_TCP=tcp:\/\/\(.*\):\(.*\)/socat_\1/')
  case "$name" in
    ''|*[!a-zA-Z0-9_]*)
      echo "[FATAL] Invalid supervisor section name '$name' — env var must follow NAME_PORT_<port>_TCP=tcp://host:port." >&2
      exit 1
      ;;
  esac

  if [ -z "$SSL" ]; then
    echo "[INFO] Initiating socat socket..."
    cmd=$(echo "$line" | sed -e 's/.*_PORT_\([0-9]*\)_TCP=tcp:\/\/\(.*\):\(.*\)/socat -d -d TCP4-LISTEN:\1,fork,reuseaddr TCP4:\2:\3/')
  else
    if [ "$SSL" = "server" ]; then
      echo "[INFO] Initiating socat server..."
      if [ -f /etc/client.crt ]; then
        echo "[INFO] ...server is VERIFYING certificates"
        cmd=$(echo "$line" | sed -e 's/.*_PORT_\([0-9]*\)_TCP=tcp:\/\/\(.*\):\(.*\)/socat -d -d OPENSSL-LISTEN:\1,fork,reuseaddr,cert=\/etc\/server.pem,cafile=\/etc\/client.crt,verify=1 TCP4:\2:\3/')
      else
        echo "[WARN ] ============================================================"
        echo "[WARN ] SECURITY WARNING: SSL=server connection is ENCRYPTED but"
        echo "[WARN ] NOT AUTHENTICATED. MITM attacks are possible."
        echo "[WARN ] Provide CLIENT_PUBLIC_KEY[_FILE] to enable authentication."
        echo "[WARN ] ============================================================"
        cmd=$(echo "$line" | sed -e 's/.*_PORT_\([0-9]*\)_TCP=tcp:\/\/\(.*\):\(.*\)/socat -d -d OPENSSL-LISTEN:\1,fork,reuseaddr,cert=\/etc\/server.pem,verify=0 TCP4:\2:\3/')
      fi
    else
      echo "[INFO] Initiating socat client..."
      if [ -f /etc/server.crt ]; then
        echo "[INFO] ...client is VERIFYING certificates"
        cmd=$(echo "$line" | sed -e 's/.*_PORT_\([0-9]*\)_TCP=tcp:\/\/\(.*\):\(.*\)/socat -d -d TCP-LISTEN:\1,reuseaddr,fork OPENSSL:\2:\3,cert=\/etc\/client.pem,cafile=\/etc\/server.crt,verify=1/')
      else
        echo "[WARN ] ============================================================"
        echo "[WARN ] SECURITY WARNING: SSL=client connection is ENCRYPTED but"
        echo "[WARN ] NOT AUTHENTICATED. MITM attacks are possible."
        echo "[WARN ] Provide SERVER_PUBLIC_KEY[_FILE] to enable authentication."
        echo "[WARN ] ============================================================"
        cmd=$(echo "$line" | sed -e 's/.*_PORT_\([0-9]*\)_TCP=tcp:\/\/\(.*\):\(.*\)/socat -d -d TCP-LISTEN:\1,reuseaddr,fork OPENSSL:\2:\3,cert=\/etc\/client.pem,verify=0/')
      fi
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

echo ":: socat.ini ::"
echo "---------------"
[ -f /etc/supervisor.d/socat.ini ] && cat /etc/supervisor.d/socat.ini
exec supervisord -n -c /etc/supervisord.conf
