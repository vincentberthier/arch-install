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
    
    print_success "Systemd services configured"
}
