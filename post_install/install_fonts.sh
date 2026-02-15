#!/usr/bin/env bash
set -euo pipefail

# Install custom fonts from a private GitHub repository.
# Run this AFTER chezmoi has deployed SSH keys.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

readonly FONT_REPO="git@github.com:vincentberthier/fonts.git"
readonly FONT_ZIP="DankMono.zip"

install_custom_fonts() {
	if fc-list | grep -qi "dank mono"; then
		print_success "Dank Mono already installed, skipping"
		return
	fi

	print_status "Installing custom fonts from private repo"

	local tmpdir
	tmpdir="$(mktemp -d)"
	trap 'rm -rf "$tmpdir"' EXIT

	if ! git clone --depth 1 "$FONT_REPO" "$tmpdir/fonts"; then
		print_error "Failed to clone font repo (are SSH keys set up?)"
		return 1
	fi

	if [[ ! -f "$tmpdir/fonts/${FONT_ZIP}" ]]; then
		print_error "Font zip not found in repo"
		return 1
	fi

	read -rp "Enter font zip password: " font_passwd

	mkdir -p "$tmpdir/extracted"
	if ! unzip -P "$font_passwd" "$tmpdir/fonts/${FONT_ZIP}" "*.otf" -d "$tmpdir/extracted/" 2>/dev/null; then
		print_error "Failed to extract fonts (wrong password?)"
		return 1
	fi

	doas mkdir -p /usr/share/fonts/custom
	find "$tmpdir/extracted" -name "*.otf" -exec doas cp {} /usr/share/fonts/custom/ \;
	doas fc-cache -fv

	print_success "Custom fonts installed"
}

install_custom_fonts
