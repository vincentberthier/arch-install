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
