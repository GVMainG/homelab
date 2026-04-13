---
name: shell
description: Use when writing, reviewing, or debugging shell scripts for this homelab — Bash on Debian/Ubuntu VMs (vm-db-01, vm-proxy-01) or PowerShell on the Windows workstation. Triggers on requests involving .sh/.ps1 files, CLI automation, deploy/backup/sync scripts, or interacting with remote server terminals over SSH.
---

# Shell scripting (Bash & PowerShell)

This homelab runs Bash scripts on Debian 12 / Ubuntu 22.04+ VMs and PowerShell on a Windows 11 control workstation. Follow the conventions below — they match existing scripts in `vm-db-01/` and `vm-proxy-01/`.

## Bash conventions

### Script skeleton

Every Bash script in this repo starts with:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
```

- `set -e` — exit on first error
- `set -u` — error on unset variables (force explicit defaults with `${VAR:-default}`)
- `set -o pipefail` — fail if any command in a pipe fails
- `SCRIPT_DIR` — resolves relative paths regardless of caller's CWD

### Idempotency

Deploy scripts must be safe to re-run. Patterns used in this repo:

```bash
# Guard package installs
if ! command -v dnsmasq >/dev/null 2>&1; then
    apt-get update && apt-get install -y dnsmasq
fi

# Guard config writes with a diff
if ! cmp -s "$SRC" "$DST"; then
    cp "$SRC" "$DST"
    systemctl restart dnsmasq
fi

# Guard directory creation
mkdir -p "$BACKUP_DIR"   # -p is idempotent by design
```

### Dependency checks

Validate at script start, fail fast with a clear message:

```bash
for cmd in docker git curl; do
    command -v "$cmd" >/dev/null 2>&1 || {
        echo "ERROR: $cmd is required but not installed" >&2
        exit 1
    }
done

[[ -f .env ]] || { echo "ERROR: .env missing — copy .env.example and fill in secrets" >&2; exit 1; }
```

### Root / sudo checks

Scripts that need root (e.g., `deploy-dnsmasq.sh`) check explicitly:

```bash
if [[ $EUID -ne 0 ]]; then
    echo "ERROR: run as root (sudo bash $0)" >&2
    exit 1
fi
```

### Error messages & logging

- Always send errors to stderr: `echo "ERROR: ..." >&2`
- Prefix user-facing progress with a marker so logs are scannable:

```bash
log() { echo "[$(date +%H:%M:%S)] $*"; }
log "Starting PostgreSQL backup..."
```

### Variables & quoting

- Always quote expansions: `"$var"`, `"${array[@]}"` — prevents word-splitting bugs
- Use `local` inside functions to avoid leaking scope
- Prefer `[[ ... ]]` over `[ ... ]` (safer, supports `&&`, `||`, regex)
- Assign with `readonly` for constants: `readonly BACKUP_RETENTION_DAYS=30`

### Common pitfalls to avoid

- `cd` without `||exit` — use `cd "$dir" || exit 1` when not already under `set -e`
- Parsing `ls` output — use globs or `find` instead
- Unquoted `$@` — always use `"$@"` to preserve arguments with spaces
- Checking `$?` after a command — rely on `set -e` or test directly in `if`

## PowerShell conventions

PowerShell is used on the Windows workstation for SSH orchestration, file transfer, and local automation (not on the Linux VMs).

### Script skeleton

```powershell
#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ScriptDir
```

- `Set-StrictMode -Version Latest` — catches typos in variable names (Bash `set -u` equivalent)
- `$ErrorActionPreference = 'Stop'` — non-terminating errors become terminating (Bash `set -e` equivalent)
- Require PowerShell 7+ (pwsh) — avoid Windows PowerShell 5.1 quirks

### Remote execution to VMs

Primary pattern — SSH to Linux VMs from Windows:

```powershell
# Single command
ssh gv@192.168.1.51 'cd ~/homelab/vm-db-01 && bash deploy.sh'

# Copy files
scp ./local-file gv@192.168.1.51:~/homelab/vm-db-01/

# Pull backups
scp gv@192.168.1.51:~/homelab/vm-db-01/backups/*.sql.gz ./local-backups/
```

Use `Invoke-Command` only over WinRM (not applicable here since all VMs are Linux).

### Parameters with validation

```powershell
param(
    [Parameter(Mandatory)]
    [ValidateSet('vm-db-01', 'vm-proxy-01')]
    [string]$Target,

    [ValidateNotNullOrEmpty()]
    [string]$User = 'gv'
)
```

### Common pitfalls to avoid

- Don't use aliases in scripts (`ls`, `cat`, `%`) — use full cmdlet names (`Get-ChildItem`, `Get-Content`, `ForEach-Object`) for readability
- Don't rely on `$LASTEXITCODE` without checking it explicitly after native commands — PowerShell doesn't auto-propagate exit codes
- Avoid `Write-Host` for data output — use `Write-Output` / return values so piping works

## When editing existing scripts

Before changing any `.sh` file in `vm-db-01/` or `vm-proxy-01/`, read the existing script fully — they're short and follow a consistent style. Match it. In particular:

- Keep the `SCRIPT_DIR` pattern even if your change doesn't use it — consistency
- Don't introduce new external tools (jq, yq, etc.) without checking they're on target VMs
- Preserve idempotency — if you add a new step, guard it

## Testing shell scripts locally before SSH deploy

- Bash: `bash -n script.sh` (syntax check), `shellcheck script.sh` (lint — install with `apt install shellcheck`)
- PowerShell: `Invoke-ScriptAnalyzer -Path script.ps1` (requires `PSScriptAnalyzer` module)

Both VMs are disposable in the sense that `deploy.sh` re-creates state — but backups (`vm-db-01/backups/`) are NOT disposable. Never write a script that could delete `backups/` without explicit retention logic matching `backup.sh`.
