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

# Global GPU type variable
GPU_TYPE=""

detect_gpu_type() {
    if lspci | grep -i nvidia &>/dev/null; then
        GPU_TYPE="nvidia"
        print_status "Nvidia GPU detected"
    else
        GPU_TYPE="amd"
        print_status "AMD GPU assumed"
    fi
    export GPU_TYPE
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
