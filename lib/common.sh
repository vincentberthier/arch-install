#!/usr/bin/env bash
# Common functions and variables used across all scripts

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if hostname matches a list
should_run_for_host() {
    local check_hostname="$1"
    shift
    local allowed_hosts=("$@")
    
    # If no specific hosts listed, run for all
    if [[ ${#allowed_hosts[@]} -eq 0 ]]; then
        return 0
    fi
    
    # Check if current hostname is in the allowed list
    for host in "${allowed_hosts[@]}"; do
        if [[ "$check_hostname" == "$host" ]]; then
            return 0
        fi
    done
    
    return 1
}

# Global GPU state.
#
# GPU_VENDORS lists every GPU vendor with a display-class PCI device on this
# machine -- a hybrid laptop has two, and both need their userspace stack or the
# unserved one has no driver at all. GPU_TYPE names the single vendor whose
# stack drives the session (discrete wins over integrated) and is what the
# Limine, SDDM and /etc/environment helpers key on.
GPU_TYPE=""
declare -ga GPU_VENDORS=()

detect_gpu_type() {
    local display_devices=""
    local class
    # PCI classes 0300 (VGA), 0302 (3D) and 0380 (other display) cover every
    # discrete and integrated GPU. Select on the class code rather than the
    # human-readable class name: the latter matches product names too, and a
    # "SanDisk Ultra 3D" NVMe drive is not a GPU.
    for class in 0300 0302 0380; do
        display_devices+="$(lspci -nn -d "::${class}")"$'\n'
    done

    GPU_VENDORS=()
    if grep -qi 'nvidia' <<<"$display_devices"; then
        GPU_VENDORS+=("nvidia")
    fi
    if grep -Eqi 'amd|ati technologies|advanced micro devices' <<<"$display_devices"; then
        GPU_VENDORS+=("amd")
    fi
    if grep -qi 'intel' <<<"$display_devices"; then
        GPU_VENDORS+=("intel")
    fi

    if ((${#GPU_VENDORS[@]} == 0)); then
        print_error "No display-class PCI device found; cannot pick a GPU stack"
        exit 1
    fi

    # Discrete first: on a hybrid machine the dedicated GPU is the one whose
    # environment variables and kernel parameters the session needs.
    if gpu_has_vendor nvidia; then
        GPU_TYPE="nvidia"
    elif gpu_has_vendor amd; then
        GPU_TYPE="amd"
    else
        GPU_TYPE="intel"
    fi

    print_status "GPU vendors detected: ${GPU_VENDORS[*]} (primary: ${GPU_TYPE})"
    export GPU_TYPE
}

# True when the machine has a GPU from the given vendor. Callers use this
# instead of comparing against GPU_TYPE so a hybrid machine installs both
# stacks rather than only the primary one.
gpu_has_vendor() {
    local wanted="$1"
    local vendor
    for vendor in ${GPU_VENDORS[@]+"${GPU_VENDORS[@]}"}; do
        if [[ "$vendor" == "$wanted" ]]; then
            return 0
        fi
    done
    return 1
}

# Post-install failure tracker. Each helper that installs a package appends
# a "<phase>: <package> (<reason>)" entry here on failure; main.sh prints the
# collected list at the end so failures are not lost in the scrollback.
declare -ga POST_INSTALL_FAILURES=()

record_failure() {
    local phase="$1"
    local package="$2"
    local reason="${3:-install failed}"
    POST_INSTALL_FAILURES+=("${phase}: ${package} (${reason})")
    print_warning "${phase}: failed to install ${package} (${reason})"
}

# Install a list of pacman packages in chunks. If the chunk transaction fails
# (typically because one package name is missing from the repos and pacman
# aborts the whole batch), retry each package in that chunk individually so a
# single bad name does not drop the other 19 with it. Any package that still
# fails is recorded via record_failure.
#
# Usage: install_pacman_packages <phase> <pkg...>
install_pacman_packages() {
    local phase="$1"
    shift
    local -a packages=("$@")
    local chunk_size=20
    local i

    for ((i = 0; i < ${#packages[@]}; i += chunk_size)); do
        local chunk=("${packages[@]:i:chunk_size}")
        print_status "${phase}: installing chunk of ${#chunk[@]}"

        if doas pacman -S --needed --noconfirm "${chunk[@]}"; then
            continue
        fi

        print_warning "${phase}: chunk failed, retrying packages individually"
        local pkg
        for pkg in "${chunk[@]}"; do
            if ! doas pacman -S --needed --noconfirm "$pkg"; then
                record_failure "${phase}" "$pkg"
            fi
        done
    done
}

# Install a list of AUR packages via paru, one at a time. Each failure is
# tracked so the summary at the end shows exactly what did not build.
#
# Usage: install_aur_packages <phase> <pkg...>
install_aur_packages() {
    local phase="$1"
    shift
    local -a packages=("$@")
    local pkg

    for pkg in "${packages[@]}"; do
        print_status "${phase} (AUR): installing $pkg"
        if ! paru -S --needed --noconfirm "$pkg"; then
            record_failure "${phase} (AUR)" "$pkg"
        fi
    done
}

# Enable (and optionally start) a systemd unit without letting a failure abort
# the whole install. Works for both system and --user scopes. Failures are
# recorded so they show up in the final summary.
#
# Usage: enable_service <phase> system|user <unit> [--now]
enable_service() {
    local phase="$1"
    local scope="$2"
    local unit="$3"
    local now="${4:-}"

    local -a cmd
    case "$scope" in
        system) cmd=(doas systemctl) ;;
        user) cmd=(systemctl --user) ;;
        *)
            print_error "enable_service: invalid scope '$scope'"
            return 1
            ;;
    esac

    local -a enable_args=(enable)
    if [[ "$now" == "--now" ]]; then
        enable_args+=(--now)
    fi
    enable_args+=("$unit")

    print_status "${phase}: enabling ${scope} unit ${unit}${now:+ (--now)}"
    if ! "${cmd[@]}" "${enable_args[@]}"; then
        record_failure "${phase}" "$unit" "systemctl ${scope} enable failed"
        return 1
    fi
    return 0
}

print_failure_summary() {
    echo
    if ((${#POST_INSTALL_FAILURES[@]} == 0)); then
        print_success "All tracked packages installed successfully"
        return
    fi

    print_warning "=================================================="
    print_warning "  ${#POST_INSTALL_FAILURES[@]} package(s) failed to install"
    print_warning "=================================================="
    local entry
    for entry in "${POST_INSTALL_FAILURES[@]}"; do
        echo "  - ${entry}"
    done
    echo
}

# True when this machine is a portable. Decided from hardware, never from a
# hostname list: a laptop that gets renamed, or a new one, must pick up the
# power-management and hibernation setup without this file being edited.
#
# DMI chassis types 8-10, 14, 30-32 are the portable ones (portable, laptop,
# notebook, sub-notebook, tablet, convertible, detachable). A battery is the
# corroborating signal for firmware that reports a useless chassis type.
is_laptop() {
    local chassis_type=""
    if [[ -r /sys/class/dmi/id/chassis_type ]]; then
        chassis_type="$(< /sys/class/dmi/id/chassis_type)"
    fi

    case "$chassis_type" in
        8 | 9 | 10 | 14 | 30 | 31 | 32) return 0 ;;
    esac

    # compgen returns non-zero when nothing matches, which is the answer we
    # want rather than an error under set -e.
    if compgen -G '/sys/class/power_supply/BAT*' >/dev/null; then
        return 0
    fi

    return 1
}

# Keyboard layout order. Group 0 is what a session starts in; the other groups
# are reachable through the layout-switch bind. Derived from the chassis rather
# than a hostname list, so a new machine needs no edit here.
#
# Portables lead with plain azerty because the built-in keyboard is engraved
# azerty, and because anything that latches the active group at start-up gets a
# layout that exists -- Wine and Proton have no bepo layout at all and
# synthesise a broken one. Desktops drive an external board already flashed for
# bepo, so bepo leads there.
KEYBOARD_LAYOUTS=""
KEYBOARD_VARIANTS=""
KEYBOARD_OPTIONS="grp:alt_shift_toggle"
CONSOLE_KEYMAP=""

detect_keyboard_layout() {
    if is_laptop; then
        KEYBOARD_LAYOUTS="fr,fr,us"
        KEYBOARD_VARIANTS=",bepo,"
        CONSOLE_KEYMAP="fr"
        print_status "Keyboard: azerty default, bepo second (built-in keyboard)"
    else
        KEYBOARD_LAYOUTS="fr,fr,us"
        KEYBOARD_VARIANTS="bepo,,"
        CONSOLE_KEYMAP="fr-bepo"
        print_status "Keyboard: bepo default, azerty second (external board)"
    fi

    export KEYBOARD_LAYOUTS KEYBOARD_VARIANTS KEYBOARD_OPTIONS CONSOLE_KEYMAP
}

# Global CPU vendor + microcode variables. Set by detect_cpu_vendor based on
# /proc/cpuinfo — independent from GPU_TYPE so Intel+AMD or AMD+Nvidia boxes
# get the right microcode.
CPU_VENDOR=""
CPU_MICROCODE_PKG=""
CPU_MICROCODE_IMG=""

detect_cpu_vendor() {
    local vendor_id
    vendor_id="$(awk -F': ' '/^vendor_id/ {print $2; exit}' /proc/cpuinfo)"

    case "$vendor_id" in
        GenuineIntel)
            CPU_VENDOR="intel"
            CPU_MICROCODE_PKG="intel-ucode"
            CPU_MICROCODE_IMG="intel-ucode.img"
            print_status "Intel CPU detected"
            ;;
        AuthenticAMD)
            CPU_VENDOR="amd"
            CPU_MICROCODE_PKG="amd-ucode"
            CPU_MICROCODE_IMG="amd-ucode.img"
            print_status "AMD CPU detected"
            ;;
        *)
            print_error "Unknown CPU vendor: ${vendor_id:-<empty>}"
            exit 1
            ;;
    esac

    export CPU_VENDOR CPU_MICROCODE_PKG CPU_MICROCODE_IMG
}
