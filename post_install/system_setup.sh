#!/usr/bin/env bash
# System setup functions

setup_directories() {
    print_status "Setting up user directories"
    
    # Create standard directories
    mkdir -p ~/Documents ~/Downloads ~/Pictures ~/Videos ~/Music
    mkdir -p ~/code ~/pcloud ~/vault
    mkdir -p ~/.config ~/.local/bin ~/.local/share
    
    print_success "Directories created"
}

setup_systemd_services() {
    print_status "Setting up systemd user services"
    
    # Enable user services
    systemctl --user enable pipewire
    systemctl --user enable pipewire-pulse
    systemctl --user enable wireplumber
    
    # Create update timer
    mkdir -p ~/.config/systemd/user
    
    # Daily update service
    cat > ~/.config/systemd/user/daily-update.service << 'EOF'
[Unit]
Description=Daily system update
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/bin/paru -Syu --noconfirm
ExecStart=/usr/bin/flatpak update -y

[Install]
WantedBy=default.target
EOF

    # Daily update timer (5 minutes after boot, then daily)
    cat > ~/.config/systemd/user/daily-update.timer << 'EOF'
[Unit]
Description=Daily system update timer
Requires=daily-update.service

[Timer]
OnBootSec=5min
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
EOF

    # Enable the timer
    systemctl --user daemon-reload
    systemctl --user enable daily-update.timer

    # Automount
    doas pacman -S --no-confirm udisks2 udiskie
    doas systemctl enable --now udisks2.service
    doas usermod -a -G storage,disk $USER

    mkdir -p ~/.config/autostart
cat > ~/.config/autostart/udiskie.desktop << EOF
[Desktop Entry]
Type=Application
Name=udiskie
Exec=udiskie --tray
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
EOF

    doas tee /etc/polkit-1/rules.d/50-udisks.rules << 'EOF'
polkit.addRule(function(action, subject) {
    var YES = polkit.Result.YES;
    var permission = {
        // only required for udisks1:
        "org.freedesktop.udisks.filesystem-mount": YES,
        "org.freedesktop.udisks.luks-unlock": YES,
        "org.freedesktop.udisks.drive-eject": YES,
        "org.freedesktop.udisks.drive-detach": YES,
        // only required for udisks2:
        "org.freedesktop.udisks2.filesystem-mount": YES,
        "org.freedesktop.udisks2.encrypted-unlock": YES,
        "org.freedesktop.udisks2.eject-media": YES,
        "org.freedesktop.udisks2.power-off-drive": YES,
        // required for udisks2 if using udiskie from another seat (e.g. systemd):
        "org.freedesktop.udisks2.filesystem-mount-other-seat": YES,
        "org.freedesktop.udisks2.filesystem-unmount-others": YES,
        "org.freedesktop.udisks2.encrypted-unlock-others": YES,
        "org.freedesktop.udisks2.eject-media-others": YES,
        "org.freedesktop.udisks2.power-off-drive-others": YES
    };
    if (subject.isInGroup("storage")) {
        return permission[action.id];
    }
});
EOF
    doas systemctl restart polkit
    
    print_success "Systemd services configured"
}

setup_duplicacy() {
    if ! command -v duplicacy &> /dev/null; then
        paru -S --no-confirm duplicacy
    fi

    SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
    mkdir -p "$SYSTEMD_USER_DIR"

    XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
    XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"

    echo -e "${YELLOW}Creating systemd service files...${NC}"
    cat > "$SYSTEMD_USER_DIR/duplicacy-backup.service" << 'EOF'
[Unit]
Description=Duplicacy backups

[Service]
Type=simple
ExecStart=/bin/bash -c 'set -eou pipefail; export HOME="%h"; export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"; export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"; /bin/bash "$XDG_CONFIG_HOME/duplicacy/backup.sh" duplicacy date'

[Install]
WantedBy=default.target
EOF

    # Create duplicacy-prune.service
    cat > "$SYSTEMD_USER_DIR/duplicacy-prune.service" << 'EOF'
[Unit]
Description=Duplicacy prune all backups

[Service]
Type=simple
ExecStart=/bin/bash -c 'set -eou pipefail; export HOME="%h"; export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"; /bin/bash "$XDG_CONFIG_HOME/duplicacy/prune.sh" duplicacy'

[Install]
WantedBy=default.target
EOF

    # Create duplicacy-backup.timer
    cat > "$SYSTEMD_USER_DIR/duplicacy-backup.timer" << 'EOF'
[Unit]
Description=Timer for duplicacy backups

[Timer]
Unit=duplicacy-backup.service
OnBootSec=15m
OnUnitActiveSec=60m

[Install]
WantedBy=timers.target
EOF

    # Create duplicacy-prune.timer
    cat > "$SYSTEMD_USER_DIR/duplicacy-prune.timer" << 'EOF'
[Unit]
Description=Timer for duplicacy pruning

[Timer]
Unit=duplicacy-prune.service
OnBootSec=120m

[Install]
WantedBy=timers.target
EOF

    systemctl --user daemon-reload
    echo -e "${YELLOW}Enabling and starting services...${NC}"

    # Enable the services
    systemctl --user enable duplicacy-backup.service
    systemctl --user enable duplicacy-prune.service

    # Enable and start the timers
    systemctl --user enable duplicacy-backup.timer
    systemctl --user enable duplicacy-prune.timer
    systemctl --user start duplicacy-backup.timer
    systemctl --user start duplicacy-prune.timer
}
