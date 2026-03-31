# Role: mailcow_expunge

Permanently deletes emails older than 2 weeks from all Dovecot mailboxes across Mailcow hosts. Runs inside the `dovecot-mailcow` container via `doveadm expunge`.

---

## What it does

1. Checks that `/opt/mailcow-dockerized` exists on the host
2. Runs the following command inside the Dovecot container:
   ```
   doveadm expunge -A mailbox % before 2w
   ```
   - `-A` — applies to all users
   - `mailbox %` — targets all top-level mailboxes (Inbox, Sent, Trash, Spam, etc.)
   - `before 2w` — messages older than 2 weeks

Hosts where `/opt/mailcow-dockerized` is not found are silently skipped.

> **Note:** With `maildir` storage, space is freed immediately. With `mdbox` storage, you may also need to run `doveadm purge` afterwards to reclaim disk space.

---

## Playbook

`playbook_mailcow_expunge.yml` targets the `mail_servers` group.

| Setting | Value |
|---|---|
| `serial` | `1` — one host at a time |
| `max_fail_percentage` | `100` — a failed host does not stop the rest of the fleet |
| `become` | `true` |

---

## Usage

Always use the wrapper script — it saves a timestamped log to `logs/` and preserves colors in the terminal.

### Run against the full fleet

```bash
./run_mailcow_expunge.sh
```

### Run against a single host

```bash
./run_mailcow_expunge.sh -l inbound-694-01a
```

### Run against a specific group

```bash
./run_mailcow_expunge.sh -l mail_servers
```

### Re-run only failed hosts after a failed run

```bash
./run_mailcow_expunge.sh --limit @logs/retry/playbook_mailcow_expunge.retry
```

### Dry run (no changes made)

```bash
./run_mailcow_expunge.sh --check
```

---

## Logs

Each run creates a timestamped log file:

```
logs/playbook_mailcow_expunge-YYYYMMDD-HHMMSS.log
```

ANSI color codes are stripped from log files. To review the last run:

```bash
cat logs/$(ls -t logs/playbook_mailcow_expunge-*.log | head -1)
```

If a host fails, a retry file is written to:

```
logs/retry/playbook_mailcow_expunge.retry
```

---

## Troubleshooting

### Check how much space was used before running

```bash
ssh <hostname> "df -h /"
```

### Manually run expunge on a single host

```bash
ssh <hostname> "cd /opt/mailcow-dockerized && \
  docker compose exec -T dovecot-mailcow doveadm expunge -A mailbox % before 2w"
```

### Check expunge for a specific user only

```bash
ssh <hostname> "cd /opt/mailcow-dockerized && \
  docker compose exec -T dovecot-mailcow doveadm expunge -u user@domain.com mailbox % before 2w"
```

### Check expunge for a specific mailbox only (e.g. Trash)

```bash
ssh <hostname> "cd /opt/mailcow-dockerized && \
  docker compose exec -T dovecot-mailcow doveadm expunge -A mailbox Trash before 2w"
```

### Count messages that would be expunged (dry run)

```bash
ssh <hostname> "cd /opt/mailcow-dockerized && \
  docker compose exec -T dovecot-mailcow doveadm search -A mailbox % before 2w | wc -l"
```

### Check disk usage after running

```bash
ssh <hostname> "df -h /"
```

### Check which hosts failed in the last run

```bash
cat logs/retry/playbook_mailcow_expunge.retry
```

### Review full output of the last run

```bash
less logs/$(ls -t logs/playbook_mailcow_expunge-*.log | head -1)
```
