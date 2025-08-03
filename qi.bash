#!/bin/bash

# qBittorrent-nox Static Binary Installer
# Automatically detects architecture and installs the correct binary

set -euox pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Base URL for downloads
BASE_URL="https://github.com/userdocs/qbittorrent-nox-static/releases/latest/download"

# Function to print colored output
print_status() {
	echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
	echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
	echo -e "${RED}[ERROR]${NC} $1"
}

print_debug() {
	if [[ ${DEBUG:-0} == "1" ]]; then
		echo -e "${BLUE}[DEBUG]${NC} $1"
	fi
}

# Function to detect Linux distribution
detect_distro() {
	local distro="unknown"

	if [[ -f /etc/os-release ]]; then
		# shellcheck source=/dev/null
		source /etc/os-release
		distro="${ID:-unknown}"
		print_debug "Detected distro from /etc/os-release: $distro"
	elif [[ -f /etc/debian_version ]]; then
		distro="debian"
		print_debug "Detected distro from /etc/debian_version: $distro"
	elif [[ -f /etc/redhat-release ]]; then
		distro="rhel"
		print_debug "Detected distro from /etc/redhat-release: $distro"
	elif [[ -f /etc/alpine-release ]]; then
		distro="alpine"
		print_debug "Detected distro from /etc/alpine-release: $distro"
	elif [[ -f /etc/arch-release ]]; then
		distro="arch"
		print_debug "Detected distro from /etc/arch-release: $distro"
	fi

	echo "$distro"
}

# Function to detect architecture with multiple fallbacks
detect_architecture() {
	local arch=""
	local machine=""
	local dpkg_arch=""
	local uname_arch=""

	# Method 1: uname -m (most reliable)
	if command -v uname > /dev/null 2>&1; then
		uname_arch=$(uname -m)
		print_debug "uname -m output: $uname_arch"
	fi

	# Method 2: dpkg --print-architecture (Debian-based systems)
	if command -v dpkg > /dev/null 2>&1; then
		dpkg_arch=$(dpkg --print-architecture 2> /dev/null || echo "")
		print_debug "dpkg architecture: $dpkg_arch"
	fi

	# Method 3: /proc/cpuinfo fallback
	if [[ -f /proc/cpuinfo ]]; then
		machine=$(grep -m1 "^processor\|^machine\|^cpu" /proc/cpuinfo | head -1 || echo "")
		print_debug "cpuinfo: $machine"
	fi

	# Primary architecture detection based on uname -m
	case "$uname_arch" in
		x86_64 | amd64)
			arch="x86_64"
			;;
		x86 | i386 | i486 | i586 | i686)
			arch="x86"
			;;
		aarch64 | arm64)
			arch="aarch64"
			;;
		armv7* | armhf)
			arch="armv7"
			;;
		arm*)
			# Further ARM detection
			if [[ -f /proc/cpuinfo ]]; then
				if grep -q "ARMv7" /proc/cpuinfo; then
					arch="armv7"
				elif grep -q "ARMv6" /proc/cpuinfo; then
					arch="armhf"
				else
					arch="armhf" # Default ARM fallback
				fi
			else
				arch="armhf"
			fi
			;;
		*)
			print_error "Unsupported architecture: $uname_arch"
			exit 1
			;;
	esac

	# Cross-reference with dpkg on Debian-based systems
	if [[ -n $dpkg_arch ]]; then
		case "$dpkg_arch" in
			amd64)
				if [[ $arch != "x86_64" ]]; then
					print_warning "Architecture mismatch: uname says $arch, dpkg says amd64. Using x86_64."
					arch="x86_64"
				fi
				;;
			i386)
				if [[ $arch != "x86" ]]; then
					print_warning "Architecture mismatch: uname says $arch, dpkg says i386. Using x86."
					arch="x86"
				fi
				;;
			arm64)
				if [[ $arch != "aarch64" ]]; then
					print_warning "Architecture mismatch: uname says $arch, dpkg says arm64. Using aarch64."
					arch="aarch64"
				fi
				;;
			armhf)
				if [[ $arch != "armv7" && $arch != "armhf" ]]; then
					print_warning "Architecture mismatch: uname says $arch, dpkg says armhf. Using armhf."
					arch="armhf"
				fi
				;;
		esac
	fi

	print_debug "Final detected architecture: $arch"
	echo "$arch"
}

# Function to check if download tool is available
check_download_tool() {
	if command -v wget > /dev/null 2>&1; then
		echo "wget"
	elif command -v curl > /dev/null 2>&1; then
		echo "curl"
	else
		print_error "Neither wget nor curl is available. Please install one of them."
		exit 1
	fi
}

# Function to download file
download_file() {
	local url="$1"
	local output="$2"
	local tool="$3"

	print_status "Downloading from: $url"

	case "$tool" in
		wget)
			if wget -qO "$output" "$url"; then
				return 0
			else
				return 1
			fi
			;;
		curl)
			if curl -sL -o "$output" "$url"; then
				return 0
			else
				return 1
			fi
			;;
		*)
			print_error "Unknown download tool: $tool"
			return 1
			;;
	esac
}

# Function to verify downloaded binary
verify_binary() {
	local binary_path="$1"

	if [[ ! -f $binary_path ]]; then
		print_error "Downloaded binary not found: $binary_path"
		return 1
	fi

	if [[ ! -s $binary_path ]]; then
		print_error "Downloaded binary is empty: $binary_path"
		return 1
	fi

	# Check if it's an ELF binary
	if command -v file > /dev/null 2>&1; then
		local file_output
		file_output=$(file "$binary_path")
		if [[ $file_output == *"ELF"* ]]; then
			print_status "Binary verification passed: ELF executable detected"
			return 0
		else
			print_warning "Binary may not be a valid ELF executable: $file_output"
		fi
	fi

	return 0
}

# Main installation function
main() {
	print_status "qBittorrent-nox Static Binary Installer"
	print_status "========================================"

	# Detect system information
	local distro
	local arch
	local download_tool
	local binary_name
	local download_url
	local install_path="$HOME/bin/qbittorrent-nox"

	distro=$(detect_distro)
	arch=$(detect_architecture)
	download_tool=$(check_download_tool)

	print_status "Detected distribution: $distro"
	print_status "Detected architecture: $arch"
	print_status "Using download tool: $download_tool"

	# Determine binary name based on architecture
	case "$arch" in
		x86_64)
			binary_name="x86_64-qbittorrent-nox"
			;;
		x86)
			binary_name="x86-qbittorrent-nox"
			;;
		aarch64)
			binary_name="aarch64-qbittorrent-nox"
			;;
		armv7)
			binary_name="armv7-qbittorrent-nox"
			;;
		armhf)
			binary_name="armhf-qbittorrent-nox"
			;;
		*)
			print_error "No binary available for architecture: $arch"
			exit 1
			;;
	esac

	download_url="$BASE_URL/$binary_name"

	# Create bin directory
	mkdir -p "$HOME/bin"

	# Download the binary
	print_status "Downloading $binary_name..."
	if ! download_file "$download_url" "$install_path" "$download_tool"; then
		print_error "Failed to download binary from: $download_url"
		print_error "Please check your internet connection and try again."
		exit 1
	fi

	# Verify the downloaded binary
	if ! verify_binary "$install_path"; then
		print_error "Binary verification failed"
		exit 1
	fi

	# Make it executable
	chmod 755 "$install_path"
	print_status "Made binary executable: $install_path"

	# Check if ~/bin is in PATH
	if [[ ":$PATH:" != *":$HOME/bin:"* ]]; then
		print_warning '$HOME/bin is not in your PATH'
		print_status "Add the following line to your ~/.bashrc or ~/.profile:"
		echo 'export PATH="$HOME/bin:$PATH"'
		print_status "Then reload your shell with: source ~/.bashrc"
	fi

	# Display success message
	print_status "Installation completed successfully!"
	print_status "Binary installed to: $install_path"
	print_status "Architecture: $arch ($binary_name)"

	# Test if binary works
	if "$install_path" --version > /dev/null 2>&1; then
		local version
		version=$("$install_path" --version 2> /dev/null | head -1 || echo "Version check failed")
		print_status "Binary test successful: $version"
	else
		print_warning "Binary test failed - the binary may not be compatible with your system"
	fi

	print_status "You can now run: qbittorrent-nox"
}

# Handle command line arguments
while [[ $# -gt 0 ]]; do
	case $1 in
		--debug)
			DEBUG=1
			shift
			;;
		--help | -h)
			echo "Usage: $0 [OPTIONS]"
			echo ""
			echo "Options:"
			echo "  --debug    Enable debug output"
			echo "  --help     Show this help message"
			echo ""
			echo "This script automatically detects your system architecture"
			echo "and downloads the appropriate qbittorrent-nox static binary."
			echo ""
			echo "Supported architectures: x86, x86_64, armhf, armv7, aarch64"
			echo "Supported distributions: Debian, Ubuntu, Alpine, Arch, Rocky, RHEL"
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
