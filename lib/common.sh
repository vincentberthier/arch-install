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
