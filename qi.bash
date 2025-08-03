#!/bin/bash
# qBittorrent-nox Static Binary Installer
set -euo pipefail

# Colors
RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m' NC='\033[0m'
print_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Get release tag from API - no fallbacks
get_release_tag() {
	local api="https://github.com/userdocs/qbittorrent-nox-static/releases/latest/download/dependency-version.json"
	local ver="${LIBTORRENT_VERSION:-v2}"

	# Check required tools
	if ! command -v curl > /dev/null; then
		print_error "curl is required but not found"
		exit 1
	fi

	if ! command -v jq > /dev/null; then
		print_error "jq is required but not found"
		exit 1
	fi

	# Fetch and parse API response
	local response
	response=$(curl -sL "$api" 2> /dev/null) || {
		print_error "Failed to fetch release information from GitHub API"
		exit 1
	}

	if [[ -z $response ]]; then
		print_error "Empty response from GitHub API"
		exit 1
	fi

	local release_tag
	case "$ver" in
		v1)
			release_tag=$(echo "$response" | jq -r '. | "release-\(.qbittorrent)_v\(.libtorrent_1_2)"' 2> /dev/null) || {
				print_error "Failed to parse release information for LibTorrent v1"
				exit 1
			}
			;;
		v2)
			release_tag=$(echo "$response" | jq -r '. | "release-\(.qbittorrent)_v\(.libtorrent_2_0)"' 2> /dev/null) || {
				print_error "Failed to parse release information for LibTorrent v2"
				exit 1
			}
			;;
		*)
			print_error "Invalid LibTorrent version: $ver"
			exit 1
			;;
	esac

	if [[ -z $release_tag || $release_tag == "null" ]]; then
		print_error "Failed to determine release tag from API response"
		exit 1
	fi

	echo "$release_tag"
}

# Detect architecture and map to binary name
detect_arch() {
	command -v arch > /dev/null || {
		print_error "arch command not found"
		exit 1
	}
	case "$(arch)" in
		x86_64 | amd64) echo "x86_64" ;;
		i?86 | x86) echo "x86" ;;
		aarch64 | arm64) echo "aarch64" ;;
		armv7*) echo "armv7" ;;
		armv6*) echo "armhf" ;;
		*)
			print_error "Unsupported architecture: $(arch)"
			exit 1
			;;
	esac
}

# Download file using available tool
download() {
	local url="$1" output="$2"
	print_info "Downloading: $url"
	if command -v wget > /dev/null; then
		wget -qO "$output" "$url"
	elif command -v curl > /dev/null; then
		curl -sL -o "$output" "$url"
	else
		print_error "Neither wget nor curl available"
		exit 1
	fi
}

# Main installation
main() {
	print_info "qBittorrent-nox Static Binary Installer"
	print_info "========================================"

	local arch="${FORCE_ARCH:-$(detect_arch)}"
	local libtorrent_ver="${LIBTORRENT_VERSION:-v2}"
	local release_tag
	local install_path="$HOME/bin/qbittorrent-nox"

	release_tag="$(get_release_tag)"

	[[ -n ${FORCE_ARCH:-} ]] && print_warn "Forcing architecture: $arch (was: $(detect_arch))"

	print_info "Architecture: $arch"
	print_info "Download tool: $(command -v wget > /dev/null && echo wget || echo curl)"
	print_info "LibTorrent version: $libtorrent_ver"
	print_info "Release tag: $release_tag"
	print_info "Attestation verification: $(command -v gh > /dev/null && echo "enabled" || echo "disabled (gh cli not found)")"

	# Validate architecture is supported
	case "$arch" in
		x86_64 | x86 | aarch64 | armv7 | armhf)
			print_info "Architecture validated: $arch"
			;;
		*)
			print_error "Unsupported architecture for download: $arch"
			print_error "Supported architectures: x86_64, x86, aarch64, armv7, armhf"
			exit 1
			;;
	esac

	local binary_name="${arch}-qbittorrent-nox"
	local url="https://github.com/userdocs/qbittorrent-nox-static/releases/download/${release_tag}/${binary_name}"

	mkdir -p "$HOME/bin"
	download "$url" "$install_path" || {
		print_error "Download failed: $url"
		exit 1
	}

	chmod 755 "$install_path"
	[[ ! -s $install_path ]] && {
		print_error "Downloaded file is empty"
		exit 1
	}

	print_info "Installation complete: $install_path"

	# Show file checksum
	if command -v sha256sum > /dev/null; then
		local checksum
		checksum=$(sha256sum "$install_path" | cut -d' ' -f1)
		print_info "SHA256: $checksum"
	elif command -v shasum > /dev/null; then
		local checksum
		checksum=$(shasum -a 256 "$install_path" | cut -d' ' -f1)
		print_info "SHA256: $checksum"
	fi

	# Verify attestations if GitHub CLI is available
	if command -v gh > /dev/null; then
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
		print_warn "Binary test failed - may not be compatible"
	fi

	# PATH check
	[[ ":$PATH:" != *":$HOME/bin:"* ]] && {
		print_warn '$HOME/bin is not in your PATH'
		print_info 'Add to ~/.bashrc: export PATH="$HOME/bin:$PATH"'
	}

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
			echo "Architecture: $(detect_arch)"
			echo "Download tool: $(command -v wget > /dev/null && echo wget || echo curl)"
			echo "LibTorrent version: ${LIBTORRENT_VERSION:-v2}"
			echo "Release tag: $(get_release_tag)"
			echo "Base URL: https://github.com/userdocs/qbittorrent-nox-static/releases/download/$(get_release_tag)"
			echo "GitHub CLI: $(command -v gh > /dev/null && echo "available (attestations will be verified)" || echo "not available")"
			exit 0
			;;
		--help | -h)
			cat << EOF
Usage: $0 [OPTIONS]

Options:
  --check              Show system information
  --force-arch ARCH    Force architecture (x86, x86_64, armhf, armv7, aarch64)
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
