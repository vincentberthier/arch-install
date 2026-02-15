#!/usr/bin/env bash
# Disk setup functions - partitioning, formatting, mounting

prepare_disk() {
	print_status "Preparing disk $TARGET_DISK"

	# Unmount any existing mounts
	umount -R /mnt 2>/dev/null || true

	# Wipe disk
	wipefs -af "$TARGET_DISK"
	sgdisk --zap-all "$TARGET_DISK"

	# Create partitions
	print_status "Creating partitions"
	sgdisk --new=1:0:+"${BOOT_SIZE}" --typecode=1:ef00 --change-name=1:"EFI System" "$TARGET_DISK"
	sgdisk --new=2:0:+"${ROOT_SIZE}" --typecode=2:8300 --change-name=2:"Linux filesystem" "$TARGET_DISK"
	sgdisk --new=3:0:0 --typecode=3:8300 --change-name=3:"Home" "$TARGET_DISK"

	# Get partition names
	if [[ "$TARGET_DISK" =~ nvme ]]; then
		BOOT_PART="${TARGET_DISK}p1"
		ROOT_PART="${TARGET_DISK}p2"
		HOME_PART="${TARGET_DISK}p3"
	else
		BOOT_PART="${TARGET_DISK}1"
		ROOT_PART="${TARGET_DISK}2"
		HOME_PART="${TARGET_DISK}3"
	fi

	print_success "Partitions created: $BOOT_PART (boot), $ROOT_PART (root), $HOME_PART (home)"
}

format_partitions() {
	print_status "Formatting partitions"

	# Format boot partition
	mkfs.fat -F32 -n "BOOT" "$BOOT_PART"

	# Format root partition with btrfs
	mkfs.btrfs -f -L "ARCH" "$ROOT_PART"

	# Format home partition with btrfs
	mkfs.btrfs -f -L "HOME" "$HOME_PART"

	print_success "Partitions formatted"
}

create_subvolumes() {
	print_status "Creating btrfs subvolumes"

	# Mount root to create subvolumes
	mount "$ROOT_PART" /mnt

	# Create subvolumes
	for subvol in "${!SUBVOLS[@]}"; do
		btrfs subvolume create "/mnt/$subvol"
		print_status "Created subvolume: $subvol"
	done

	# Unmount
	umount /mnt

	print_success "Subvolumes created"
}

mount_filesystem() {
	print_status "Mounting filesystem"

	local mount_opts="noatime,compress=zstd:1,space_cache=v2,discard=async"

	# Mount root subvolume (no @home subvolume needed)
	mount -o "$mount_opts,subvol=@" "$ROOT_PART" /mnt

	# Create mount points and mount system subvolumes only
	for subvol in "${!SUBVOLS[@]}"; do
		if [[ "$subvol" != "@" && "$subvol" != "@home" ]]; then # Skip @home
			local mount_point="/mnt${SUBVOLS[$subvol]}"
			mkdir -p "$mount_point"
			mount -o "$mount_opts,subvol=$subvol" "$ROOT_PART" "$mount_point"
			print_status "Mounted $subvol -> $mount_point"
		fi
	done

	# Mount separate home partition (no subvolumes)
	mkdir -p /mnt/home
	mount -o "$mount_opts" "$HOME_PART" /mnt/home

	# Mount boot partition
	mkdir -p /mnt/boot
	mount "$BOOT_PART" /mnt/boot

	# Create swapfile
	print_status "Creating swapfile"
	btrfs filesystem mkswapfile --size "$SWAP_SIZE" /mnt/swap/swapfile
	swapon /mnt/swap/swapfile

	print_success "Filesystem mounted"
}
