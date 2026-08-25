#!/usr/bin/env bash
# Gaming packages installation

install_gaming_packages() {
	local packages=(
		# Gaming
		"gamemode" "lib32-gamemode" "mangohud" "lib32-mangohud"
		"steam" "lutris" "wine-staging"
		"ttf-liberation" "ttf-dejavu" "noto-fonts"
	)

	# 32-bit runtime every GPU needs for Wine and Proton.
	packages+=("lib32-libpulse" "lib32-openal" "lib32-vulkan-icd-loader")

	# Add GPU-specific gaming tools, one block per detected vendor: a hybrid
	# machine has to have both 32-bit driver stacks present, since Proton
	# picks the GPU at launch time.
	if gpu_has_vendor nvidia; then
		packages+=("nvidia-utils" "lib32-nvidia-utils" "lib32-opencl-nvidia")
	fi
	if gpu_has_vendor amd || gpu_has_vendor intel; then
		packages+=("lib32-mesa")
	fi
	if gpu_has_vendor amd; then
		packages+=("radeontop" "corectrl" "lib32-vulkan-radeon")
	fi
	if gpu_has_vendor intel; then
		packages+=("lib32-vulkan-intel")
	fi

	print_status "Installing Gaming packages (${#packages[@]} packages)"
	install_pacman_packages "gaming" "${packages[@]}"

	print_success "Gaming packages installation completed"
}
