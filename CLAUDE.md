# CLAUDE.md

Arch Linux installation automation scripts. Pure Bash, no build system, no tests.

**Required skills -- load these before any work in this repo:**

- `bash-coding` -- before writing or modifying any script
- `repo-management` -- before any VCS operation (commit, branch, describe)

## Project Overview

Two entry points orchestrate modular function libraries:

| Entry point            | Context                 | Privilege                |
|------------------------|-------------------------|--------------------------|
| `install_main.sh`      | Live ISO (base install) | Runs as root             |
| `post_install/main.sh` | Installed system        | Runs as user, uses `doas` |

`lib/` and `post_install/` files define functions only -- the orchestrators source
them and call functions in order. No file executes anything at top level.

## Commands

There is no build system, no test suite, no CI/CD. Validate scripts with:

```bash
# Lint all scripts
shellcheck install_main.sh lib/*.sh post_install/*.sh

# Lint a single script
shellcheck lib/disk_setup.sh

# Syntax check without execution
bash -n lib/common.sh

# Debug a script (trace mode)
bash -x post_install/main.sh
```

## Project-Specific Conventions

These override or supplement the `bash-coding` skill defaults.

### Strict Mode in Libraries

Entry points set `set -euo pipefail`. Library files (`lib/*.sh`, `post_install/*.sh`)
rely on the caller's strict mode -- do **not** add it to libraries.

### Logging

Use the four functions from `lib/common.sh` instead of defining new ones:

```bash
print_status  "message"   # [INFO]    blue
print_success "message"   # [SUCCESS] green
print_warning "message"   # [WARNING] yellow
print_error   "message"   # [ERROR]   red
```

### Variables

| Scope         | Convention        | Example                          |
|---------------|-------------------|----------------------------------|
| Global/config | `UPPER_SNAKE_CASE` | `TARGET_DISK`, `GPU_TYPE`       |
| Local         | `lower_snake_case` | `local mount_opts="..."`        |
| Constants     | `readonly`         | `readonly SCRIPT_DIR="..."`     |
| Associative   | `declare -A`       | `declare -A SUBVOLS=([k]="v")` |

### Script Path Resolution

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
```

### Privilege Escalation

- `doas` is the primary escalation tool, not `sudo`
- `sudo` is configured only for software that hardcodes it (snapper, pacman wrappers)

### Package Installation

Chunk large package arrays to avoid command-line limits:

```bash
local packages=(pkg1 pkg2 ... pkg40)
local chunk_size=20
for ((i=0; i<${#packages[@]}; i+=chunk_size)); do
    local chunk=("${packages[@]:i:chunk_size}")
    if ! doas pacman -S --needed --noconfirm "${chunk[@]}"; then
        print_warning "Some packages in chunk failed, continuing..."
    fi
done
```

AUR packages use `paru -S --needed --noconfirm` individually.

### Error Handling Tiers

Beyond what the `bash-coding` skill prescribes, this project uses three tiers:

- **Hard exit** for critical preconditions: `print_error "..."; exit 1`
- **Soft warning** for non-critical package failures: `print_warning "...continuing"`
- **Silent suppression** for expected failures: `umount -R /mnt 2>/dev/null || true`

### Heredocs

| Syntax                    | When to use                                      |
|---------------------------|--------------------------------------------------|
| `<< 'EOF'`               | Config files that must be literal (no expansion) |
| `<< EOF`                  | Templates needing variable interpolation         |
| Nested in `arch-chroot`  | Base install in-chroot operations                |

Escape `$` as `\$` inside unquoted heredocs when you need a literal dollar sign.

### Host-Based Conditional Logic

```bash
if should_run_for_host "$HOSTNAME" "athena" "gaia" "hephaistos"; then
    install_desktop_packages
fi
```

Known hosts: `athena`, `gaia`, `hephaistos`.

### GPU Detection

Automatic via `lspci | grep -i nvidia` / `amd`. The `detect_gpu_type` function in
`lib/common.sh` sets `GPU_TYPE` to `"nvidia"`, `"amd"`, or `"unknown"`.

## File Organization

Each `.sh` file under `lib/` and `post_install/` is a pure function library -- it
defines functions but never calls them at top level. The orchestrator scripts
(`install_main.sh`, `post_install/main.sh`) source all libraries and call functions
in the desired order.

When adding new functionality:

1. Add functions to the appropriate existing file by concern
2. Source the file in the orchestrator if not already sourced
3. Call the function at the right phase in the orchestrator

## Version Control

Uses Jujutsu (`jj`), not raw git. Commit messages are short, imperative, lowercase,
no trailing period: `add thunar`, `fix duplicacy scripts`, `split scripts for modularity`.
