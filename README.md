# Docker Ambassador with SSL capabilities

* Based on https://github.com/bandesz/docker-ambassador
* Based on https://github.com/md5/ctlc-docker-ambassador and https://github.com/zbyte64/stowaway-ssl-ambassador
* Based on the Ambassador pattern: https://docs.docker.com/articles/ambassador_pattern_linking/
* Based on alpine
* Uses socat for relaying traffic
* Uses supervisor for monitoring the socat processes
  * every tunnel is monitored individually


( mysql-client -> client-ambassador ) --> network --> ( server-ambassador -> mysql-server )


## Testing

Two VM instances are used for this test - a server and a client one.

### Run server service
```
docker run --name mysql-server -e MYSQL_ROOT_PASSWORD=pass -d mysql
```

### Run server ambassador

```
docker run -d --link mysql-server:mysql-server --name server-ambassador \
        -p 3306:3306 jnovack/ambassador
```

### Run client ambassador

Use the server's ip instead of 1.2.3.4

```
docker run -d --name client-ambassador --expose 3306 \
        -e MYSQL_PORT_3306_TCP=tcp://1.2.3.4:3306 jnovack/ambassador
```

### Run client (for simplicity I use the same docker image as for the server)
```
docker run -it --link mysql-ambassador:mysql-server \
        --name mysql-client mysql bash
```


## Enable SSL

### Generate server keys

```Shell
openssl genrsa -out server.key 4096
openssl req -new -key server.key -x509 -days 3653 -out server.crt
cat server.key server.crt > server.pem
```

For enhanced security, copy `server.crt` to the client and provide `SERVER_PUBLIC_KEY` (see below).

### Generate client keys
```Shell
openssl genrsa -out client.key 4096
openssl req -new -key client.key -x509 -days 3653 -out client.crt
cat client.key client.crt > client.pem
```

For enhanced security, copy `client.crt` to the client and provide `CLIENT_PUBLIC_KEY` (see below).

### Run server ambassador

```
docker run -d --name mysql-ambassador \
       --link mysql-server:mysql-server -p 3306:3306 \
       -e SERVER_PRIVATE_KEY="`cat server.pem`" \
       -e SSL_ENABLE="server" \
       -e CLIENT_PUBLIC_KEY="`cat client.crt`" \
       jnovack/ambassador
```

If you provide `CLIENT_PUBLIC_KEY`, only clients with certificates matching in `client.crt` will be permitted to connect.

If you do not provide `CLIENT_PUBLIC_KEY` any client may connect.

### Run client ambassador

```
docker run -d --name mysql-ambassador --expose 3306 \
       -e MYSQL_PORT_3306_TCP=tcp://1.2.3.4:3306
       -e CLIENT_PRIVATE_KEY="`cat client.pem`" -e SSL_ENABLE="client" \
       -e SERVER_PUBLIC_KEY="`cat server.crt`" \
       jnovack/ambassador
```

If you provide a `SERVER_PUBLIC_KEY`, you will only be able to connect to the servers with certificates in `server.crt`.

If you do not provide `SERVER_PUBLIC_KEY`, then the server will not be verified, but still encrypted.
