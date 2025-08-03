#!/bin/bash

# qBittorrent-nox Static Binary Installer
# Automatically detects architecture and installs the correct binary

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Base URL for downloads
BASE_URL="https://github.com/userdocs/qbittorrent-nox-static/releases/latest/download"

# Function to print colored output
print_info() {
	echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
	echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
	echo -e "${RED}[ERROR]${NC} $1"
}

# Function to detect architecture using arch command
detect_architecture() {
	if ! command -v arch > /dev/null 2>&1; then
		print_error "arch command not found"
		exit 1
	fi

	local arch_output
	arch_output=$(arch)

	case "$arch_output" in
		x86_64 | amd64)
			echo "x86_64"
			;;
		i386 | i486 | i586 | i686 | x86)
			echo "x86"
			;;
		aarch64 | arm64)
			echo "aarch64"
			;;
		armv7l | armv7*)
			echo "armv7"
			;;
		armv6l | armv6*)
			echo "armhf"
			;;
		*)
			print_error "Unsupported architecture: $arch_output"
			print_error "Supported: x86, x86_64, armhf, armv7, aarch64"
			exit 1
			;;
	esac
}

# Function to check if download tool is available
get_download_tool() {
	if command -v wget > /dev/null 2>&1; then
		echo "wget"
	elif command -v curl > /dev/null 2>&1; then
		echo "curl"
	else
		print_error "Neither wget nor curl is available"
		exit 1
	fi
}

# Function to download file
download_file() {
	local url="$1"
	local output="$2"
	local tool="$3"

	print_info "Downloading: $url"

	case "$tool" in
		wget)
			wget -qO "$output" "$url"
			;;
		curl)
			curl -sL -o "$output" "$url"
			;;
	esac
}

# Main function
main() {
	print_info "qBittorrent-nox Static Binary Installer"
	print_info "========================================"

	# Get architecture and download tool
	local arch
	local download_tool
	local binary_name
	local install_path="$HOME/bin/qbittorrent-nox"

	arch=$(detect_architecture)
	download_tool=$(get_download_tool)

	# Override architecture if forced
	if [[ -n ${FORCE_ARCH:-} ]]; then
		print_warn "Forcing architecture: $FORCE_ARCH (was: $arch)"
		arch="$FORCE_ARCH"
	fi

	print_info "Architecture: $arch"
	print_info "Download tool: $download_tool"

	# Map architecture to binary name
	case "$arch" in
		x86_64) binary_name="x86_64-qbittorrent-nox" ;;
		x86) binary_name="x86-qbittorrent-nox" ;;
		aarch64) binary_name="aarch64-qbittorrent-nox" ;;
		armv7) binary_name="armv7-qbittorrent-nox" ;;
		armhf) binary_name="armhf-qbittorrent-nox" ;;
		*)
			print_error "No binary available for: $arch"
			exit 1
			;;
	esac

	# Create bin directory and download
	mkdir -p "$HOME/bin"

	print_info "Downloading $binary_name..."
	if ! download_file "$BASE_URL/$binary_name" "$install_path" "$download_tool"; then
		print_error "Download failed: $BASE_URL/$binary_name"
		exit 1
	fi

	# Make executable and verify
	chmod 755 "$install_path"

	if [[ ! -s $install_path ]]; then
		print_error "Downloaded file is empty"
		exit 1
	fi

	print_info "Installation complete: $install_path"

	# Test the binary
	if "$install_path" --version > /dev/null 2>&1; then
		local version
		version=$("$install_path" --version | head -1)
		print_info "Version: $version"
	else
		print_warn "Binary test failed - may not be compatible"
	fi

	# PATH check
	if [[ ":$PATH:" != *":$HOME/bin:"* ]]; then
		print_warn '$HOME/bin is not in your PATH'
		print_info 'Add to ~/.bashrc: export PATH="$HOME/bin:$PATH"'
	fi

	print_info "Run with: qbittorrent-nox"
}

# Handle command line arguments
while [[ $# -gt 0 ]]; do
	case $1 in
		--force-arch)
			FORCE_ARCH="$2"
			shift 2
			;;
		--check)
			echo "Architecture: $(detect_architecture)"
			echo "Download tool: $(get_download_tool)"
			exit 0
			;;
		--help | -h)
			echo "Usage: $0 [OPTIONS]"
			echo ""
			echo "Options:"
			echo "  --check              Show system information"
			echo "  --force-arch ARCH    Force architecture (x86, x86_64, armhf, armv7, aarch64)"
			echo "  --help               Show this help"
			echo ""
			echo "Automatically downloads the correct qbittorrent-nox static binary"
			echo "for your architecture using the 'arch' command."
			exit 0
			;;
		*)
			print_error "Unknown option: $1"
			echo "Use --help for usage information"
			exit 1
			;;
	esac
done

# Run main function
main
