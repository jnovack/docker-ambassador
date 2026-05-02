# ADR 0002: Supervisor INI Section Name Validation

- Status: Accepted
- Date: 2026-05-01

## Context

`entrypoint.sh` builds a supervisord INI file dynamically from environment variables
matching `_TCP=`. The section name (`$name`) is written directly as `[program:$name]`.
If `$name` contains `]` or a newline, the INI header is malformed and a crafted value
could inject an additional `[program:]` block — giving the attacker an arbitrary
supervisord process entry inside the container.

## Findings

- `$name` is derived by applying a sed substitution to the full `NAME=value` env line.
  The substitution pattern is `s/.*_PORT_\([0-9]*\)_TCP=tcp:\/\/.*/socat_\1/`, which
  extracts only the numeric port and prefixes it with `socat_`.
- When the substitution **matches**, `$name` is always `socat_<digits>` — inherently
  safe. The sed match requires a literal `_PORT_<digits>_TCP=tcp://` in the line, so
  a correctly formed env var cannot produce an unsafe name.
- When the substitution **does not match** (malformed or non-standard env var that still
  contains `_TCP=`), sed returns the input unchanged. The full `NAME=value` string
  becomes `$name`, which contains `=`, `/`, `:`, and potentially any character present
  in the value — none of which are valid in `[a-zA-Z0-9_]+`.
- The `grep _TCP=` pre-filter is the only gate before the sed step; it passes any line
  containing the literal `_TCP=`, including malformed ones like `HACK_TCP=tcp://...`.
- AGENTS.md explicitly requires: "Validate supervisor INI section names before writing
  (`^[a-zA-Z0-9_]+$`)."
- `$cmd` is also unvalidated but its content goes into the `command=` value line, not
  a section header; a newline in `$cmd` could still inject a key/value pair but cannot
  open a new `[program:]` section. That is a separate, lower-severity issue not
  addressed here.

## Alternatives Considered

### Option 1: Sanitize `$name` by stripping invalid characters

Rejected. Silent sanitization masks operator error (a misconfigured env var that should
have been caught). In this repo, env vars are operator-supplied at container start time;
a typo that produces a mangled supervisor section name is a configuration error, not a
recoverable condition.

### Option 2: Validate `$name` with `grep -E '^[a-zA-Z0-9_]+$'`

Rejected in favor of a `case` statement. `grep -E` (ERE) is not guaranteed by POSIX and
the shebang is `#!/bin/sh`. Alpine's busybox grep does support `-E`, but relying on it
would be a bashism-adjacent dependency. The `case` pattern `''|*[!a-zA-Z0-9_]*)` is
pure POSIX sh and carries no external dependency.

### Option 3: Validate `$name` with a POSIX `case` statement, exit on failure

Accepted. A two-branch `case` covers empty string and any string containing a character
outside `[a-zA-Z0-9_]`. It requires no subshell, no external tool, and exits immediately
with a clear `[FATAL]` message before any file is written.

## Decision

After the sed derivation of `$name`, add:

```sh
case "$name" in
  ''|*[!a-zA-Z0-9_]*)
    echo "[FATAL] Invalid supervisor section name '$name' — ..." >&2
    exit 1
    ;;
esac
```

Exit 1 aborts the container before any supervisor config is written.

## Consequences

### Positive

- Eliminates the INI injection path entirely: no unsafe name ever reaches the heredoc.
- Failure mode is loud and immediate — `[FATAL]` in logs, non-zero exit, container does
  not start — making misconfiguration visible rather than silent.
- Zero new dependencies; pure POSIX sh.

### Tradeoffs

- A container with a single malformed `_TCP=` var will refuse to start entirely, even
  if other valid `_TCP=` vars are present. There is no partial-start mode.
- The check fires on any `_TCP=` line that slips past the grep filter and fails the sed
  pattern; operators who set non-standard env var names containing `_TCP=` for unrelated
  purposes will see an unexpected FATAL.

## What Replaces It

Replaces the previous behavior of silently writing `[program:<garbage>]` to the
supervisor INI and allowing supervisord to start with a malformed config file.

## Revisit Criteria

- If the `_TCP=` env var convention is extended to support non-numeric port identifiers
  (e.g., named ports), the sed pattern and the validation regex would both need updating.
- If `$cmd` injection (newline in host/port values) is addressed, a companion validation
  should be added at the same site.

## References

- [rootfs/entrypoint.sh](../../rootfs/entrypoint.sh)
- [test/docker-compose.test.yml](../../test/docker-compose.test.yml)
- [AGENTS.md](../../AGENTS.md)
