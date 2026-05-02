# ADR 0001: Testing verify=0 Warning Output via Shared Volume in SUT

- Status: Accepted
- Date: 2026-05-01

## Context

`entrypoint.sh` falls back to `socat`'s `verify=0` when SSL is enabled but no peer CA
cert is provided. The connection is encrypted but unauthenticated, and the original
warning was a single `[WARN]` line easy to miss in startup noise. The fix (a prominent
five-line block) needed test coverage asserting the warning actually appears in container
output.

## Findings

- The existing test suite (`test/docker-compose.test.yml`) is a Docker Compose
  integration suite. The `sut` container verifies data flows end-to-end via `socat` and
  `nc`; it has no Docker socket access and cannot call `docker logs` on peer containers.
- `docker compose up --exit-code-from SERVICE` implies `--abort-on-container-exit`:
  **any** container that exits causes Compose to stop all remaining containers
  immediately. A helper service designed to exit quickly will kill the rest of the suite
  mid-run. Discovered 2026-05-01 when exit code 2 (scenario B data-path failure) was
  produced by `warn-server` exiting after 2 seconds and aborting the live `sut`.
- The `bootloader` service already demonstrates the correct pattern for a helper that
  must outlive the suite: run work, then `sleep 300; exit 1`.
- Scenarios B (`server-b`, `client-b`) already exercise `verify=0` paths but their
  stdout is not accessible to the `sut` container.

## Alternatives Considered

### Option 1: Standalone shell script (`test/test-warn.sh`) + separate `make test-warn` target

Rejected. Splits the test suite across two mechanisms (`make test` and `make test-warn`),
making it easy to forget one. Requires the built image tag to be passed explicitly and
ties the test to the host's Docker CLI rather than living entirely inside the Compose
workflow.

### Option 2: Inspect logs of existing scenario-B containers from `sut`

Rejected. The `sut` container is on the compose network but has no Docker socket mount
and no way to call `docker logs`. Injecting the socket would give the test container
host-level privileges, which is inappropriate for a portable CI test.

### Option 3: Write warning to a shared volume from existing `server-b` / `client-b`

Rejected. Those services are data-path fixtures; redirecting their stdout to a file
would suppress their normal Docker log output and couple a functional concern (routing
test traffic) to an observability concern (log assertion).

### Option 4: Dedicated `warn-server` / `warn-client` services writing to a shared volume, staying alive for the test duration

Accepted. Two new services run `entrypoint.sh` in the background with their output
redirected to `/warn/server.log` and `/warn/client.log` on a named volume. They then
`sleep 300; exit 1` to remain alive until Compose tears down the suite. The `sut`
mounts the same volume and `grep`s the log files after the data-path scenarios complete.

## Decision

Add `warn-server` and `warn-client` services to `docker-compose.test.yml`. Each runs
`entrypoint.sh > /warn/<role>.log 2>&1 &` then sleeps 300 seconds. The `sut` mounts the
`warn` volume and asserts `SECURITY WARNING` appears in both log files (exit codes 6 and
7 on failure). This is scenario F in the suite.

## Consequences

### Positive

- Warning coverage lives inside `make test` alongside all other scenarios; nothing extra
  to run.
- The `sut` assertion is a simple `grep -q` on a file — no new tooling or dependencies.
- Pattern is consistent with how `bootloader` handles helper-service lifetime.

### Tradeoffs

- Two additional containers start per test run, each running `openssl` cert generation
  and spawning `supervisord` + `socat` for 300 seconds (or until Compose teardown).
- The 300-second sleep is a blunt instrument; it cannot signal "I'm done writing" to
  the `sut`. The `sut` relies on the fact that entrypoint startup completes well before
  the data-path wait loop finishes.
- If `entrypoint.sh` startup ever becomes slow enough that the log files are not written
  before scenario F runs, the test will produce a false negative.

## Revisit Criteria

- If Docker Compose adds a `depends_on: condition: service_completed_successfully`
  workflow that does not imply `--abort-on-container-exit`, the sleep pattern could be
  replaced with a clean exit.
- If the test suite grows a mechanism for capturing per-service log files centrally
  (e.g., a log aggregator sidecar), the shared volume approach could be retired.

## References

- [rootfs/entrypoint.sh](../../rootfs/entrypoint.sh)
- [test/docker-compose.test.yml](../../test/docker-compose.test.yml)
- [docs/TESTING.md](../TESTING.md)
