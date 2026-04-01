# Testing

The file `test/docker-compose.test.yml` is the end-to-end test harness for this
project.  It can be run locally with `make docker-test` and is designed to serve
as the CI validation step on every release.

## Overview

The ambassador container's only reason to exist is to proxy TCP connections with
optional mutual TLS.  The tests therefore exercise all five meaningful operating
modes:

| Scenario | SSL | Server cert | Client cert      | Verify srv | Verify client       |
|----------|-----|-------------|------------------|------------|---------------------|
| A        | No  | —           | —                | —          | —                   |
| B        | Yes | auto-gen    | auto-gen         | no         | no                  |
| C        | Yes | provided    | provided         | yes        | no                  |
| D        | Yes | provided    | provided (pinned)| yes        | yes (cert pinning)  |
| E        | Yes | provided    | CA-signed        | yes        | yes (CA trust)      |

Scenarios D and E both use mutual TLS but differ in how the server verifies the
client: D pins a specific client certificate; E trusts any certificate issued by
a known CA.  This distinction is important for multi-client deployments where
issuing individual pinned certs per client is impractical.

Each scenario independently verifies the full data path from the `sut` container
through one or two ambassador containers to the `backend` echo server and back.

## Topology

```text
  sut ──► client-a:7000 ────────────────────────────────────────────────► backend:5000  (A)
  sut ──► client-b:11000 ───[TLS, no verify]────► server-b:11001 ───────► backend:5000  (B)
  sut ──► client-c:12000 ───[TLS, verify srv]───► server-c:12001 ───────► backend:5000  (C)
  sut ──► client-d:13000 ───[TLS, mutual]───────► server-d:13001 ───────► backend:5000  (D)
  sut ──► client-e:14000 ───[TLS, CA-signed]────► server-e:14001 ───────► backend:5000  (E)
```

All containers share a single `testnet` bridge network (`203.0.113.0/24` is not
required here because all services can resolve by hostname).

## Services

### bootloader

Runs `openssl req` to generate a server cert+key pair and a client cert+key pair,
writes them to the shared `certs` volume, then touches `/certs/ready` and sleeps
for up to 5 minutes.

The sleep is intentional: `--exit-code-from sut` implies `--abort-on-container-exit`,
so the bootloader must stay alive for the duration of the test.  `exit 1` at the
end of the sleep gives a clear failure signal if the test takes longer than expected
(which it should not).

Ambassador services that require provided certs (scenarios C and D) wait for
`/certs/ready` in their entrypoint wrapper before calling the real
`/usr/bin/entrypoint.sh`.

### backend

A `socat TCP-LISTEN:5000,fork,reuseaddr EXEC:'cat'` echo server.  Every TCP
connection receives exactly what it sends, then the connection is closed.  This is
the simplest possible way to verify that data traversed the entire proxy chain
intact.

### ambassador-a (scenario A)

A single ambassador instance with no `SSL` env var set.  Listens on plain TCP port
7000 and forwards to `backend:5000`.  Exercises the basic socat relay path.

### server-b / client-b (scenario B)

Two ambassador instances, both using auto-generated certificates and `verify=0`.

- `server-b`: `SSL=server`, no `SERVER_PRIVATE_KEY_FILE` / `SERVER_PUBLIC_CERT_FILE` → auto-generates, no
  `CLIENT_PUBLIC_KEY_FILE` → does not verify the client.
- `client-b`: `SSL=client`, no `CLIENT_PRIVATE_KEY_FILE` / `CLIENT_PUBLIC_CERT_FILE` → auto-generates, no
  `SERVER_PUBLIC_KEY_FILE` → does not verify the server.

The connection is encrypted but neither peer is authenticated.  This exercises
the auto-cert generation code path.

### server-c / client-c (scenario C)

Two ambassador instances using bootloader-generated certificates.

- `server-c`: `SSL=server`, `SERVER_PRIVATE_KEY_FILE=/certs/server-c.key`,
  `SERVER_PUBLIC_CERT_FILE=/certs/server-c.crt`, no `CLIENT_PUBLIC_KEY_FILE` → does not require a client cert.
- `client-c`: `SSL=client`, `CLIENT_PRIVATE_KEY_FILE=/certs/client.key`,
  `CLIENT_PUBLIC_CERT_FILE=/certs/client.crt`,
  `SERVER_PUBLIC_KEY_FILE=/certs/server-c.crt` → verifies the server.

The client authenticates the server; the server accepts any connecting client.

### server-d / client-d (scenario D)

Two ambassador instances using bootloader-generated certificates with full mutual
authentication.

- `server-d`: `SSL=server`, `SERVER_PRIVATE_KEY_FILE=/certs/server-d.key`,
  `SERVER_PUBLIC_CERT_FILE=/certs/server-d.crt`,
  `CLIENT_PUBLIC_KEY_FILE=/certs/client.crt` → requires and verifies a client cert.
- `client-d`: `SSL=client`, `CLIENT_PRIVATE_KEY_FILE=/certs/client.key`,
  `CLIENT_PUBLIC_CERT_FILE=/certs/client.crt`,
  `SERVER_PUBLIC_KEY_FILE=/certs/server-d.crt` → verifies the server.

Both peers present and verify certificates.  The server pins the specific client
certificate — only that exact certificate is accepted.

### server-e / client-e (scenario E)

Two ambassador instances demonstrating CA-based client certificate trust.

- `server-e`: `SSL=server`, `SERVER_PRIVATE_KEY_FILE=/certs/server-e.key`,
  `SERVER_PUBLIC_CERT_FILE=/certs/server-e.crt`,
  `CLIENT_PUBLIC_KEY_FILE=/certs/ca.crt` — the CA certificate, **not** the
  client's certificate. The server will accept any client whose certificate was
  signed by this CA.
- `client-e`: `SSL=client`, `CLIENT_PRIVATE_KEY_FILE=/certs/client-e.key`,
  `CLIENT_PUBLIC_CERT_FILE=/certs/client-e.crt` (signed by the CA),
  `SERVER_PUBLIC_KEY_FILE=/certs/server-e.crt` → verifies the server.

The bootloader generates the CA with `openssl req -new -x509`, then signs the
client cert with `openssl x509 -req -CA ca.crt -CAkey ca.key` rather than
creating a self-signed cert.  This is the difference from scenario D: the
client cert is not self-signed and not pinned — it derives trust from the CA.

This mode is the correct choice when you have many clients or want to rotate
client credentials without reconfiguring the server.

### sut

The System Under Test runner.  Waits for each ambassador's listen port to be open
(using `nc -z`), then sends a unique test string through each scenario using
`socat` and asserts it echoes back unchanged.

Exit codes:

- `0` — all five scenarios passed
- `1` — scenario A failed
- `2` — scenario B failed
- `3` — scenario C failed
- `4` — scenario D failed
- `5` — scenario E failed

## Running the tests

```sh
# Full clean run (recommended — nukes all images/volumes from previous runs)
make docker-test

# Bring up interactively to watch logs
make docker-up

# Tear down containers and volumes but keep images
make docker-clean

# Nuclear option: remove everything including images
make docker-nuke
```

## Network notes

The `testnet` network uses Docker's default bridge driver with automatic IP
assignment.  All inter-service communication uses Docker's built-in DNS (service
name = hostname).  No fixed IP addresses are required.

The address space `203.0.113.0/24` (TEST-NET-3 per RFC 5737) is not used here
but is available if you need a reference for assigning fixed IPs in a future expansion.
