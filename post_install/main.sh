#!/usr/bin/env bash
set -euo pipefail

# Post-Installation Main Orchestrator
# Run this script after the base installation as your user

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOSTNAME="$(hostname)"

# Source all modules
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/gpu_specific.sh"

# Source installation modules
source "${SCRIPT_DIR}/packages_core.sh"
source "${SCRIPT_DIR}/packages_desktop.sh"
source "${SCRIPT_DIR}/packages_development.sh"
source "${SCRIPT_DIR}/packages_gaming.sh"
source "${SCRIPT_DIR}/system_setup.sh"
source "${SCRIPT_DIR}/user_setup.sh"

main() {
	print_status "=================================================="
	print_status "  Post-Installation Package Setup"
	print_status "  Host: $HOSTNAME"
	print_status "=================================================="

	# Check if running as user (not root)
	if [[ $EUID -eq 0 ]]; then
		print_error "Do not run this script as root"
		exit 1
	fi

	# Detect GPU type
	detect_gpu_type

	print_status "Starting package installation process..."

	# Phase 1: Essential setup
	setup_directories
	update_system
	install_paru

	# Phase 2: Core packages (all hosts)
	install_core_packages

	# Phase 3: Desktop packages (desktop hosts only)
	# Example: only install on specific hosts
	if should_run_for_host "$HOSTNAME" "athena" "gaia" "hephaistos"; then
		install_desktop_packages
		setup_display_manager
	fi

	# Phase 4: Development packages
	if should_run_for_host "$HOSTNAME" "athena" "gaia" "hephaistos"; then
		install_development_packages
		install_podman
	fi

	# Phase 5: Gaming packages (gaming hosts only)
	if should_run_for_host "$HOSTNAME" "athena" "gaia"; then
		install_gaming_packages
	fi

	# Phase 6: User environment setup
	setup_shell_environment
	setup_systemd_services
	setup_virtualization
	setup_duplicacy_config
	setup_duplicacy

	# Phase 7: GPU-specific setup
	if [[ "$GPU_TYPE" == "nvidia" ]] && should_run_for_host "$HOSTNAME" "athena"; then
		setup_nvidia_environment
	fi

	# Phase 8: Embedded/electronics tools (gaia only)
	if should_run_for_host "$HOSTNAME" "gaia"; then
		install_embedded_packages
	fi

	# Phase 9: Astro tools (gaia only)
	if should_run_for_host "$HOSTNAME" "gaia"; then
		install_astro_tools
	fi

	print_success "Package installation completed!"
	echo
	print_success "Installation Summary:"
	echo "  - System packages installed"
	echo "  - AUR helper (paru) configured"
	echo "  - Fish shell with plugins configured"
	echo "  - Systemd services set up"
	echo "  - User directories created"
	echo
	print_warning "Next Steps:"
	echo "1. Configure 1Password integration"
	echo "2. Set up 'chezmoi init https://github.com/vincentberthier/dotfiles.git'"
	echo "3. Apply chezmoi conf 'chezmoi apply' twice"
	echo "4. Run ~/post_install/install_fonts.sh to install custom fonts"
	echo "5. Log out and back in to apply all changes"
	echo
	print_status "Manual tasks remaining:"
	echo "- Fine-tune niri configuration"

	# Offer to reboot
	echo
	read -rp "Reboot now to apply all changes? (y/n): " reboot_now
	if [[ "$reboot_now" == "y" ]]; then
		doas reboot
	fi
}

# Run main function
main "$@"
