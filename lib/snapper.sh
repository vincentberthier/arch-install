#!/usr/bin/env bash
# Snapper configuration

setup_snapper() {
    print_status "Setting up Snapper"
    
    arch-chroot /mnt /bin/bash << 'EOF'
# Create snapper config for root (let it create its own .snapshots)
snapper -c root create-config /

# Don't delete snapper's subvolume or try to replace it
# The previous approach was wrong - let snapper manage its own subvolume

# Set snapper configuration
cat > /etc/snapper/configs/root << 'SNAPPER_EOF'
SUBVOLUME="/"
FSTYPE="btrfs"
QGROUP=""
SPACE_LIMIT="0.5"
FREE_LIMIT="0.2"
ALLOW_USERS=""
ALLOW_GROUPS=""
SYNC_ACL="no"
BACKGROUND_COMPARISON="yes"
NUMBER_CLEANUP="yes"
NUMBER_MIN_AGE="1800"
NUMBER_LIMIT="50"
NUMBER_LIMIT_IMPORTANT="10"
TIMELINE_CREATE="yes"
TIMELINE_CLEANUP="yes"
TIMELINE_MIN_AGE="1800"
TIMELINE_LIMIT_HOURLY="5"
TIMELINE_LIMIT_DAILY="7"
TIMELINE_LIMIT_WEEKLY="4"
TIMELINE_LIMIT_MONTHLY="0"
TIMELINE_LIMIT_YEARLY="0"
SNAPPER_EOF

# Enable snapper services
systemctl enable snapper-timeline.timer
systemctl enable snapper-cleanup.timer

EOF

    print_success "Snapper configured"
}
