# ADR 0003: CERT_CN Env Var for Auto-Generated Certificate Subject and SAN

- Status: Accepted
- Date: 2026-05-01

## Context

When `SSL=server` or `SSL=client` is set without providing a key/cert pair, `entrypoint.sh`
auto-generates a self-signed certificate. The subject CN was hardcoded to
`server.ambassador.local` or `client.ambassador.local`. These values are meaningless as
hostnames in any real deployment, and — more critically — neither cert included a Subject
Alternative Name (SAN). Modern TLS stacks (Go, Chrome, OpenSSL 1.1+) validate SANs for
hostname verification and ignore the CN entirely. Any peer running `verify=1` against an
auto-generated cert would fail hostname verification regardless of what CN was set.

## Findings

- The image ships OpenSSL 3.3.7 (Alpine 3.21, verified 2026-05-01), which supports
  `-addext "subjectAltName=DNS:..."` in `openssl req`. No additional packages needed.
- `openssl req -addext` was introduced in OpenSSL 1.1.1 (2018); it is safe to depend on
  for any Alpine image ≥ 3.12.
- The `CERT_CN` value is used as both the CN in `-subj` and the DNS SAN in `-addext`.
  A single env var covers both; splitting them into separate vars would add complexity
  with no practical benefit (the CN and SAN should be the same hostname).
- `CERT_CN` has no effect when a key/cert pair is provided explicitly — it is only
  consulted on the auto-generate path.
- The existing Scenario B (auto-cert / no peer verification) continues to pass because
  `verify=0` ignores the SAN; the default CN value change is backward-compatible.

## Alternatives Considered

### Option 1: Accept `CERT_CN` only in `-subj`, document that SANs are absent

Rejected. This would make the env var useful only for cosmetic labelling: modern TLS
stacks ignore the CN for hostname verification, so a custom CN without a matching SAN
still fails `verify=1`. The purpose of the env var is to produce a cert that passes
peer verification; omitting the SAN would make it a no-op for that goal.

### Option 2: Accept separate `CERT_CN` and `CERT_SAN` env vars

Rejected. The DNS SAN and the CN should always be the same value for a simple proxy
cert. Splitting them adds two env vars, extra documentation, and the possibility of
operator error (mismatched CN/SAN). A single `CERT_CN` that controls both is simpler
and covers all practical use cases.

### Option 3: Accept `CERT_CN` for both CN and DNS SAN (accepted)

Accepted. One env var, two uses. Defaults preserve the previous CN values
(`server.ambassador.local` / `client.ambassador.local`).

## Decision

Add `CERT_CN` env var. On the auto-generate path, set `_cert_cn="${CERT_CN:-<default>}"`
and pass it to both `-subj "...CN=${_cert_cn}"` and `-addext "subjectAltName=DNS:${_cert_cn}"`.
Document in `README.md` under a new "Certificate generation" section.

## Consequences

### Positive

- Auto-generated certs now include a SAN, making them valid for hostname verification by
  modern TLS stacks when the operator sets `CERT_CN` to the service's actual hostname.
- Zero new dependencies; `-addext` is built into the OpenSSL already in the image.
- Backward-compatible: omitting `CERT_CN` produces the same cert structure as before,
  just now with a SAN matching the old hardcoded CN.

### Tradeoffs

- Auto-generated certs are still self-signed; they require either `verify=0` or explicit
  trust injection. `CERT_CN` does not make them CA-signed.
- The operator must know the hostname their peer will connect to and set `CERT_CN`
  accordingly. There is no automatic hostname discovery.
- Server and client ambassadors each have their own `CERT_CN`; there is no shared
  default that matches both.

## What Replaces It

Replaces hardcoded `server.ambassador.local` / `client.ambassador.local` CNs with a
configurable value that also populates the SAN extension.

## Revisit Criteria

- If IP-based connections become common (not DNS hostnames), `CERT_CN` would need to
  also emit an IP SAN (`IP:<addr>`). Currently only `DNS:` SANs are emitted.
- If auto-generated certs should be CA-signed (e.g. using an injected CA key), the
  entire auto-generate path would need reworking beyond this env var.

## References

- [rootfs/entrypoint.sh](../../rootfs/entrypoint.sh)
- [test/docker-compose.test.yml](../../test/docker-compose.test.yml)
- [README.md](../../README.md)
