#!/bin/bash
# qBittorrent-nox Static Binary Installer
set -euo pipefail

set -x

# Colors
RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m' NC='\033[0m'
print_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if command exists
has_command() {
	command -v "$1" > /dev/null
}

# Comprehensive dependency and system validation
validate_system() {
	local missing_deps=()
	local errors=()

	print_info "Validating system dependencies and environment..."

	# Check for download tools
	if ! has_command curl && ! has_command wget; then
		missing_deps+=("curl or wget")
		errors+=("No download tool available. Install curl or wget.")
	fi

	# Check for architecture detection tools
	if ! has_command arch && ! has_command apk && ! has_command dpkg; then
		missing_deps+=("arch, apk, or dpkg")
		errors+=("Architecture detection tool missing. Install coreutils/util-linux (arch), alpine-tools (apk), or dpkg.")
	fi

	# Check for checksum tools
	if ! has_command sha256sum && ! has_command shasum; then
		print_warn "No checksum tool found (sha256sum/shasum) - file verification will be skipped"
	fi

	# Validate architecture if detection tools exist
	local detected_arch=""
	if has_command arch; then
		detected_arch="$(arch)"
	elif has_command apk; then
		detected_arch="$(apk --print-arch 2> /dev/null || echo "")"
	elif has_command dpkg; then
		detected_arch="$(dpkg --print-architecture 2> /dev/null || echo "")"
	fi

	if [[ -n $detected_arch ]]; then
		case "$detected_arch" in
			x86_64 | amd64 | x86 | i386 | i686 | aarch64 | arm64 | armv7* | armv6* | riscv64 | armhf | armel)
				: # Architecture is supported
				;;
			*)
				errors+=("Unsupported architecture: $detected_arch. Supported: x86_64, x86, i386, i686, aarch64, armv7, armhf, riscv64")
				;;
		esac
	fi

	# Report all issues at once
	if [[ ${#missing_deps[@]} -gt 0 ]] || [[ ${#errors[@]} -gt 0 ]]; then
		print_error "System validation failed!"

		if [[ ${#missing_deps[@]} -gt 0 ]]; then
			print_error "Missing dependencies: ${missing_deps[*]}"
		fi

		if [[ ${#errors[@]} -gt 0 ]]; then
			print_error "System issues found:"
			for error in "${errors[@]}"; do
				print_error "  - $error"
			done
		fi

		print_error "Please resolve the above issues and try again."
		exit 1
	fi

	print_info "✓ System validation passed"
}

# Get download tool preference (wget preferred, curl fallback)
get_download_tool() {
	if has_command wget; then
		echo "wget"
	elif has_command curl; then
		echo "curl"
	else
		echo ""
	fi
}

# Detect and map architecture to binary name
detect_arch() {
	local arch_output=""

	# Try different architecture detection methods
	if has_command arch; then
		arch_output="$(arch)"
	elif has_command apk; then
		arch_output="$(apk --print-arch 2> /dev/null || echo "")"
	elif has_command dpkg; then
		arch_output="$(dpkg --print-architecture 2> /dev/null || echo "")"
	fi

	case "$arch_output" in
		x86_64 | amd64) echo "x86_64" ;;
		x86 | i386 | i686) echo "x86" ;;
		aarch64 | arm64) echo "aarch64" ;;
		armv7* | armhf) echo "armv7" ;;
		armv6* | armel) echo "armhf" ;;
		riscv64) echo "riscv64" ;;
		*) echo "" ;;
	esac
}

# Validate architecture is supported for download
validate_arch() {
	local arch="$1"
	case "$arch" in
		x86_64 | x86 | aarch64 | armv7 | armhf | riscv64)
			print_info "Architecture validated: $arch"
			;;
		*)
			print_error "Architecture '$arch' not supported for binary download"
			print_error "Supported: x86_64, x86, aarch64, armv7, armhf, riscv64"
			exit 1
			;;
	esac
}

# Get release tag from API
get_release_tag() {
	local api="https://github.com/userdocs/qbittorrent-nox-static/releases/latest/download/dependency-version.json"
	local ver="${LIBTORRENT_VERSION:-v2}"

	# Fetch API response using available tool
	local response tool
	tool=$(get_download_tool)
	case "$tool" in
		wget) response=$(wget -qO- "$api" 2> /dev/null) ;;
		curl) response=$(curl -sL "$api" 2> /dev/null) ;;
		*)
			print_error "No download tool available (wget/curl)"
			exit 1
			;;
	esac

	[[ -n $response ]] || {
		print_error "Failed to fetch release information from GitHub API"
		exit 1
	}

	# Parse release tag based on LibTorrent version using sed
	local release_tag
	case "$ver" in
		v1)
			local qbt_ver libt_ver
			qbt_ver=$(echo "$response" | sed -rn 's|(.*)"qbittorrent": "(.*)",|\2|p')
			libt_ver=$(echo "$response" | sed -rn 's|(.*)"libtorrent_1_2": "(.*)",|\2|p')
			release_tag="release-${qbt_ver}_v${libt_ver}"
			;;
		v2)
			local qbt_ver libt_ver
			qbt_ver=$(echo "$response" | sed -rn 's|(.*)"qbittorrent": "(.*)",|\2|p')
			libt_ver=$(echo "$response" | sed -rn 's|(.*)"libtorrent_2_0": "(.*)",|\2|p')
			release_tag="release-${qbt_ver}_v${libt_ver}"
			;;
		*)
			print_error "Invalid LibTorrent version: $ver"
			exit 1
			;;
	esac

	[[ -n $release_tag && $release_tag != "null" ]] || {
		print_error "Failed to parse release tag from API response"
		exit 1
	}

	echo "$release_tag"
}

# Download file using available tool
download() {
	local url="$1" output="$2"
	local tool
	tool=$(get_download_tool)

	print_info "Downloading: $url"
	case "$tool" in
		wget) wget -qO "$output" "$url" ;;
		curl) curl -sL -o "$output" "$url" ;;
		*)
			print_error "No download tool available (wget/curl)"
			exit 1
			;;
	esac
}

# Get file checksum if tools available
get_checksum() {
	local file="$1"
	if has_command sha256sum; then
		sha256sum "$file" | cut -d' ' -f1
	elif has_command shasum; then
		shasum -a 256 "$file" | cut -d' ' -f1
	fi
}

# Main installation
main() {
	print_info "qBittorrent-nox Static Binary Installer"
	print_info "========================================"

	# Validate system first
	validate_system

	local arch="${FORCE_ARCH:-$(detect_arch)}"
	local libtorrent_ver="${LIBTORRENT_VERSION:-v2}"
	local install_path="$HOME/bin/qbittorrent-nox"

	# Display configuration
	[[ -n ${FORCE_ARCH:-} ]] && print_warn "Forcing architecture: $arch (detected: $(detect_arch))"
	print_info "Architecture: $arch"
	print_info "Download tool: $(get_download_tool)"
	print_info "LibTorrent version: $libtorrent_ver"
	print_info "Attestation verification: $(has_command gh && echo "enabled" || echo "disabled (gh cli not found)")"

	# Validate architecture is supported
	validate_arch "$arch"

	# Get release information
	local release_tag
	release_tag="$(get_release_tag)"
	print_info "Release tag: $release_tag"

	# Prepare download
	local binary_name="${arch}-qbittorrent-nox"
	local url="https://github.com/userdocs/qbittorrent-nox-static/releases/download/${release_tag}/${binary_name}"

	# Download and install
	mkdir -p "$HOME/bin"
	download "$url" "$install_path" || {
		print_error "Download failed: $url"
		exit 1
	}

	chmod 755 "$install_path"
	[[ -s $install_path ]] || {
		print_error "Downloaded file is empty or corrupt"
		exit 1
	}

	print_info "Installation complete: $install_path"

	# Show file checksum if available
	local checksum
	checksum=$(get_checksum "$install_path")
	[[ -n $checksum ]] && print_info "SHA256: $checksum"

	# Verify attestations if GitHub CLI available
	if has_command gh; then
		print_info "Verifying attestations with GitHub CLI..."
		if gh attestation verify "$install_path" --repo userdocs/qbittorrent-nox-static 2> /dev/null; then
			print_info "✓ Attestations verified successfully"
		else
			print_warn "⚠ Attestation verification failed or not available"
		fi
	else
		print_warn "GitHub CLI not found - skipping attestation verification"
	fi

	# Test binary
	if "$install_path" --version > /dev/null 2>&1; then
		print_info "Version: $("$install_path" --version | head -1)"
	else
		print_warn "Binary test failed - may not be compatible with this system"
	fi

	# PATH check and guidance
	if [[ ":$PATH:" != *":$HOME/bin:"* ]]; then
		print_warn '$HOME/bin is not in your PATH'
		print_info 'Add to ~/.bashrc: export PATH="$HOME/bin:$PATH"'
	fi

	print_info "Run with: qbittorrent-nox"
}

# Command line arguments
while [[ $# -gt 0 ]]; do
	case $1 in
		--force-arch)
			FORCE_ARCH="$2"
			shift 2
			;;
		--libtorrent)
			case "$2" in
				v1 | v2) LIBTORRENT_VERSION="$2" ;;
				1) LIBTORRENT_VERSION="v1" ;;
				2) LIBTORRENT_VERSION="v2" ;;
				*)
					print_error "Invalid libtorrent version: $2. Use: v1, v2, 1, or 2"
					exit 1
					;;
			esac
			shift 2
			;;
		--check)
			validate_system
			echo "Architecture: $(detect_arch)"
			echo "Download tool: $(get_download_tool)"
			echo "LibTorrent version: ${LIBTORRENT_VERSION:-v2}"
			echo "Release tag: $(get_release_tag)"
			echo "Base URL: https://github.com/userdocs/qbittorrent-nox-static/releases/download/$(get_release_tag)"
			echo "GitHub CLI: $(has_command gh && echo "available (attestations will be verified)" || echo "not available")"
			echo "Checksum tools: $(has_command sha256sum && echo "sha256sum" || has_command shasum && echo "shasum" || echo "none available")"
			exit 0
			;;
		--help | -h)
			cat << EOF
Usage: $0 [OPTIONS]

Options:
  --check              Show system information
  --force-arch ARCH    Force architecture (x86, x86_64, armhf, armv7, aarch64, riscv64)
  --libtorrent VER     LibTorrent version (v1, v2, 1, 2) [default: v2]
  --help               Show this help

Environment Variables:
  LIBTORRENT_VERSION   LibTorrent version (v1, v2) [default: v2]
  FORCE_ARCH           Force architecture override

Examples:
  $0                   # Install with LibTorrent v2 (default)
  $0 --libtorrent v1   # Install with LibTorrent v1
  $0 --check           # Show system info and versions
  LIBTORRENT_VERSION=v1 $0  # Install with LibTorrent v1 via env var
EOF
			exit 0
			;;
		*)
			print_error "Unknown option: $1. Use --help for usage information"
			exit 1
			;;
	esac
done

main
