#!/usr/bin/env bash
set -euo pipefail

# Clean up the live ISO environment after a failed install so install_main.sh
# can be re-run. Turns off swap, unmounts /mnt recursively, and clears any
# stale device-mapper / loop / btrfs state tied to the target disk.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

if [[ $EUID -ne 0 ]]; then
	print_error "cleanup.sh must run as root (live ISO context)"
	exit 1
fi

disable_swap() {
	print_status "Disabling swap"

	# Turn off any swapfile living under /mnt first (btrfs swapfile from a
	# previous run), then fall back to swapoff -a for anything else.
	if [[ -f /mnt/swap/swapfile ]]; then
		swapoff /mnt/swap/swapfile 2>/dev/null || true
	fi
	swapoff -a 2>/dev/null || true

	if swapon --show --noheadings | grep -q .; then
		print_warning "Some swap devices are still active:"
		swapon --show
	else
		print_success "All swap disabled"
	fi
}

unmount_mnt() {
	print_status "Unmounting /mnt tree"

	if ! mountpoint -q /mnt && ! findmnt -R /mnt &>/dev/null; then
		print_success "/mnt already clean"
		return
	fi

	# Try a clean recursive unmount a few times (handles mounts that free up
	# once a child is detached), then fall back to a lazy unmount.
	local _
	for _ in 1 2 3; do
		if umount -R /mnt 2>/dev/null; then
			print_success "/mnt unmounted"
			return
		fi
		sleep 1
	done

	print_warning "Clean unmount failed, falling back to lazy unmount"
	umount -Rl /mnt 2>/dev/null || true

	if findmnt -R /mnt &>/dev/null; then
		print_error "/mnt still has mounts after lazy unmount:"
		findmnt -R /mnt || true
		exit 1
	fi
	print_success "/mnt lazy-unmounted"
}

release_target_disk() {
	local disk="${1:-}"
	if [[ -z "$disk" ]]; then
		return
	fi

	if [[ ! -b "$disk" ]]; then
		print_warning "Target disk $disk is not a block device, skipping"
		return
	fi

	print_status "Releasing holders on $disk"

	# Unmount every partition of $disk that's still mounted anywhere on the
	# system (not just under /mnt).
	local part mountpoint
	while read -r part mountpoint; do
		[[ -z "$part" ]] && continue
		print_status "Unmounting $part from $mountpoint"
		umount "$mountpoint" 2>/dev/null || umount -l "$mountpoint" 2>/dev/null || true
	done < <(lsblk -nrpo NAME,MOUNTPOINT "$disk" | awk '$2 != ""')

	# Close any device-mapper holders (LUKS, LVM) pointing at $disk.
	local holder
	while read -r holder; do
		[[ -z "$holder" ]] && continue
		print_status "Removing dm holder $holder"
		dmsetup remove "$holder" 2>/dev/null || true
	done < <(lsblk -nrpo NAME,TYPE "$disk" | awk '$2 == "crypt" || $2 == "lvm" {print $1}')
}

main() {
	local target_disk="${1:-}"

	print_status "=================================================="
	print_status "  Arch install cleanup"
	print_status "=================================================="

	disable_swap
	unmount_mnt
	release_target_disk "$target_disk"

	print_success "Cleanup complete"
	if [[ -n "$target_disk" ]]; then
		echo
		print_status "Final state of $target_disk:"
		lsblk "$target_disk" || true
	fi
}

main "$@"
