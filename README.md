# correctness-checks

Monitoring templates that ask **"is it still doing its job?"** instead of
**"is it responding?"**

Uptime checks tell you a service is reachable. They cannot tell you it stopped
being useful. These are shell templates for the second question, designed to
push to [Uptime Kuma](https://github.com/louislam/uptime-kuma) — but the pattern
works with any push-based monitor.

---

## Why this exists

A homelab ran 22 uptime monitors. All green, for months. Then a routine audit
found three services that had been quietly broken the whole time:

| Service | Broken since | What the monitor saw |
|---|---|---|
| **Samba** | ~5 months | Port 445 open, TCP accepted — but every login was rejected |
| **Vaultwarden backups** | 9 days | A valid, fully extractable `.tar.gz` — without the database in it |
| **Portainer** | 4 months | HTTP 200 on the login page — but it had lost its Docker connection |

Not one of them was an outage. Every one of them would have been a disaster on
the day it mattered. The uptime checks were not wrong — they were answering a
different question than the one that mattered.

The backup case is the sharpest. The backup script hit a permission error
partway through, so `tar` aborted — but it had already written the files it
*could* read. The result was a structurally perfect archive missing the one
file worth backing up. `tar -tzf` returns 0 for that. Nine days of green.

## The rule

> **Do the real work the service exists for, then assert on the result.**

Concretely, for each check:

1. **Perform the actual operation** — log in, resolve a name, read a row,
   list an archive. Not a health endpoint.
2. **Assert on the outcome, not the status code.** `HTTP 200` and `{"ok":true}`
   are not evidence.
3. **Test the negative too.** A DNSSEC validator that accepts a knowingly
   broken signature passes a positive-only test while protecting nothing.
4. **"Cannot verify" is a failure.** Every path that cannot reach a verdict
   must fail loudly. Silently skipping unparseable output is how a check
   starts lying.
5. **Push success as well as failure.** With a push monitor, the *absence* of a
   success push turns the monitor red on its own. That makes every check a
   dead man's switch: if the script stops running at all, you find out.

## Included checks

| Check | Asserts |
|---|---|
| `backup-archive.sh` | Newest archive is recent **and contains** a named file |
| `disk-smart.sh` | NVMe wear, media errors, spare blocks below threshold |
| `dns-dnssec.sh` | Valid signature authenticated **and** broken one rejected |
| `dns-blocking.sh` | Test domains blocked **and** a control domain still resolves |
| `http-json.sh` | A JSON field exists, is numeric, and is above a floor |
| `00-template.sh` | Skeleton for writing your own |

## Setup

```bash
git clone <this repo> && cd correctness-checks
cp config.example.env config.env && chmod 600 config.env
$EDITOR config.env                       # KUMA_BASE + one token per check
./checks/disk-smart.sh                   # try one
```

Create a **Push** monitor in Uptime Kuma for each check, copy its token into
`config.env`, then run the checks from cron:

```cron
17 */6 * * *  /path/to/checks/disk-smart.sh      >> /var/log/cc-smart.log 2>&1
*/15 * * * *  /path/to/checks/dns-dnssec.sh      >> /var/log/cc-dnssec.log 2>&1
30 4  * * *   /path/to/checks/backup-archive.sh  >> /var/log/cc-backup.log 2>&1
```

Set each monitor's **heartbeat interval slightly longer than its cron
interval**. If the script dies, the missing push turns it red by itself.

## Tests

```bash
./tests/run-tests.sh
```

Pushes go to `tests/kuma-stub.py`, never to a real monitor. That is structural,
not a convention: while writing these checks we copied one for testing and left
the **real** push token in it. The simulated failure went to the production
monitor and turned it red.

## Three traps worth knowing

**`cmd | grep -q` under `set -o pipefail` returns 141.** `grep` closes after its
first match, the producer gets `SIGPIPE`, and the pipeline reports failure —
even though the match was found. Read into a variable first, then test it.
This produced a false "backup incomplete" alarm on a provably complete archive.

**`python3 - <<'PY'` cannot take piped data.** `python3 -` reads the *program*
from stdin, so the heredoc replaces your input and the script sees nothing.
Put the parser in its own file (see `lib/json-field.py`). The same applies to
`python3 -c "..."` in double quotes, where the shell expands `$` inside your
source first.

**A missing executable raises, it does not return a code.** Testing a failure
path by pointing at a nonexistent binary throws `FileNotFoundError` before your
error handling runs — so both the broken and the fixed version fail identically
and you have proven nothing. Use a stub that *exists* and exits non-zero.

## License

MIT
