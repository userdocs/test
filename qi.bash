#!/bin/bash
# qBittorrent-nox Static Binary Installer
set -euo pipefail

# Colors
RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m' NC='\033[0m'
print_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if command exists
has_command() {
	command -v "$1" > /dev/null
}

# Detect architecture and map to binary name
detect_arch() {
	local arch_output=""

	# Try different architecture detection methods
	# Prioritize distribution-specific tools for better accuracy
	if has_command apk; then
		arch_output="$(apk --print-arch 2> /dev/null || echo "")"
	elif has_command dpkg; then
		arch_output="$(dpkg --print-architecture 2> /dev/null || echo "")"
	elif has_command arch; then
		arch_output="$(arch)"
	else
		print_error "No architecture detection tool found (arch/apk/dpkg)"
		exit 1
	fi

	case "$arch_output" in
		# x86_64 = amd64, x86_64
		x86_64 | amd64) echo "x86_64" ;;
		# x86 = x86, i386, i686
		x86 | i386 | i686) echo "x86" ;;
		# aarch64 = arm64, aarch64
		aarch64 | arm64) echo "aarch64" ;;
		# armv7 = armv7* (and armhf on Debian/Ubuntu)
		armv7*) echo "armv7" ;;
		# armhf = armhf (on Alpine = armv6), armv6*, armel
		armhf)
			# Alpine uses apk, Debian/Ubuntu use dpkg
			if has_command apk; then
				echo "armhf" # Alpine: armhf stays as armhf (armv6 binary)
			else
				echo "armv7" # Debian/Ubuntu: armhf maps to armv7 binary
			fi
			;;
		armv6* | armel) echo "armhf" ;;
		# riscv64 = riscv64
		riscv64) echo "riscv64" ;;
		*)
			print_error "Unsupported architecture: $arch_output"
			exit 1
			;;
	esac
}

# Get download tool
get_download_tool() {
	if has_command wget; then
		echo "wget"
	elif has_command curl; then
		echo "curl"
	else
		print_error "No download tool found (wget/curl)"
		exit 1
	fi
}

# Get release tag from API
get_release_tag() {
	local api="https://github.com/userdocs/qbittorrent-nox-static/releases/latest/download/dependency-version.json"
	local ver="${LIBTORRENT_VERSION:-v2}"
	local tool
	tool=$(get_download_tool)

	# Fetch API response
	local response
	case "$tool" in
		wget) response=$(wget -qO- "$api" 2> /dev/null) ;;
		curl) response=$(curl -sL "$api" 2> /dev/null) ;;
	esac

	[[ -n $response ]] || {
		print_error "Failed to fetch release information"
		exit 1
	}

	# Parse release tag
	local qbt_ver libt_ver
	qbt_ver=$(echo "$response" | sed -rn 's|(.*)"qbittorrent": "(.*)",|\2|p')

	case "$ver" in
		v1) libt_ver=$(echo "$response" | sed -rn 's|(.*)"libtorrent_1_2": "(.*)",|\2|p') ;;
		v2) libt_ver=$(echo "$response" | sed -rn 's|(.*)"libtorrent_2_0": "(.*)",|\2|p') ;;
		*)
			print_error "Invalid LibTorrent version: $ver"
			exit 1
			;;
	esac

	echo "release-${qbt_ver}_v${libt_ver}"
}

# Download file
download() {
	local url="$1" output="$2"
	local tool
	tool=$(get_download_tool)

	print_info "Downloading: $url"
	case "$tool" in
		wget) wget -qO "$output" "$url" ;;
		curl) curl -sL -o "$output" "$url" ;;
	esac
}

# Main installation
main() {
	print_info "qBittorrent-nox Static Binary Installer"
	print_info "========================================"

	local arch="${FORCE_ARCH:-$(detect_arch)}"
	local libtorrent_ver="${LIBTORRENT_VERSION:-v2}"
	local install_path="$HOME/bin/qbittorrent-nox"

	print_info "Architecture: $arch"
	print_info "Download tool: $(get_download_tool)"
	print_info "LibTorrent version: $libtorrent_ver"

	# Get release and download
	local release_tag
	release_tag=$(get_release_tag)
	local url="https://github.com/userdocs/qbittorrent-nox-static/releases/download/${release_tag}/${arch}-qbittorrent-nox"

	mkdir -p "$HOME/bin"
	download "$url" "$install_path"
	chmod 755 "$install_path"

	[[ -s $install_path ]] || {
		print_error "Download failed or file is empty"
		exit 1
	}

	print_info "Installation complete: $install_path"

	# Show checksum if available
	if has_command sha256sum; then
		local checksum
		checksum=$(sha256sum "$install_path" | cut -d' ' -f1)
		print_info "SHA256: $checksum"
	fi

	# Test binary
	if "$install_path" --version > /dev/null 2>&1; then
		print_info "Version: $("$install_path" --version | head -1)"
	else
		print_warn "Binary test failed"
	fi

	# PATH check
	if [[ ":$PATH:" != *":$HOME/bin:"* ]]; then
		print_warn '$HOME/bin is not in your PATH'
		print_info 'Add to ~/.bashrc: export PATH="$HOME/bin:$PATH"'
	fi

	print_info "Run with: qbittorrent-nox"
}

# Simple argument parsing
case "${1:-}" in
	--help | -h)
		cat << EOF
Usage: $0 [OPTIONS]

Options:
  --libtorrent VER     LibTorrent version (v1, v2) [default: v2]
  --help               Show this help

Environment Variables:
  LIBTORRENT_VERSION   LibTorrent version (v1, v2) [default: v2]
  FORCE_ARCH           Force architecture (x86_64, x86, aarch64, armv7, armhf, riscv64)

Examples:
  $0                   # Install with LibTorrent v2
  $0 --libtorrent v1   # Install with LibTorrent v1
  FORCE_ARCH=armv7 $0  # Force armv7 architecture
EOF
		exit 0
		;;
	--libtorrent)
		case "${2:-}" in
			v1 | v2) LIBTORRENT_VERSION="$2" ;;
			*)
				print_error "Invalid libtorrent version. Use: v1 or v2"
				exit 1
				;;
		esac
		;;
	"") : ;; # No arguments, proceed with defaults
	*)
		print_error "Unknown option: $1. Use --help for usage"
		exit 1
		;;
esac

main
