# Changelog

## 2026-03-26

### Bug Fixes

#### `install.yml` — version parse crash (fleet-wide)

`regex_search(..., '\1')` returns Python `None` when the pattern doesn't match.
`None | default([])` does **not** replace `None` (default only replaces Undefined).
`None | first` then crashes with `'NoneType' object is not iterable`.

Fix: use `| default(['0.0.0'], true)` (the `true` flag replaces falsy values including None)
and guard `_dd_version_raw.stdout` with `| default('')` for the case where the prior
task was skipped and the register variable has no stdout key.

```yaml
# before (broken)
| regex_search('Agent (\d+\.\d+\.\d+)', '\1') | first | default('0.0.0')

# after (fixed)
(_dd_version_raw.stdout | default(''))
| regex_search('Agent (\d+\.\d+\.\d+)', '\1')
| default(['0.0.0'], true)
| first
```

#### `install.yml` — `Show installed agent version` crash in check mode

`_dd_version_post.stdout_lines[0]` raises index-out-of-bounds in `--check` mode
because `command` tasks skip execution and return an empty lazy list.

Fix: added `check_mode: false` to `Confirm agent binary is present` so the command
always runs, and guarded the debug message with `| default([]) | first | default(...)`.

#### `validate_agent.yml` — `Wait for Datadog agent to become active` loops forever in check mode

`command: systemctl is-active datadog-agent` skips in `--check` mode, returning empty
stdout. The `until: stdout == 'active'` condition never passes, burning all 15 retries
(~5 minutes per host, across the entire fleet simultaneously).

Fix: added `check_mode: false` to both `Wait for Datadog agent to become active` and
`Check agent status`, and guarded `stdout_lines[:25]` with `| default([])` and a `when`.

### Monitor Fix

`docker.service_up` monitor was scoped to `type:inbound` but the agent emits
`mail_type:inbound`. Monitor scope corrected to `mail_type:inbound`.

### CLAUDE.md Updates

- Added **Check Mode** section documenting the `check_mode: false` pattern for read-only
  command tasks and why it is required.
- Added **Datadog Monitor Tag Reference** table listing all emitted tags and their values,
  with explicit note that `mail_type:inbound` is the correct scope tag (not `type:inbound`).
- Added known limitation for `regex_search` + `default` + `first` filter chain behavior.
