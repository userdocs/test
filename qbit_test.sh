#!/usr/bin/env bash
#
apt-get update
apt-get upgrade -y
apt-get install -y build-essential curl pkg-config automake libtool git perl python3 python3-dev unzip graphviz zlib1g-dev libssl-dev libgeoip-dev cmake ninja-build
apt-get install -y libqt5svg5-dev qtbase5-dev qttools5-dev
#
boost_version="$(git ls-remote -q -t --refs https://github.com/boostorg/boost.git | awk '{sub("refs/tags/boost-", "");sub("(.*)(rc|alpha|beta)(.*)", ""); print $2 }' | awk '!/^$/' | sort -rV | head -n1)"
#
curl -sNLk https://boostorg.jfrog.io/artifactory/main/release/${boost_version}/source/boost_${boost_version//./_}.tar.gz -o "$HOME/boost_${boost_version//./_}.tar.gz"
tar xf "$HOME/boost_${boost_version//./_}.tar.gz" -C "$HOME"
#
git clone --shallow-submodules --recurse-submodules https://github.com/arvidn/libtorrent.git ~/libtorrent && cd ~/libtorrent
# git checkout $(git tag -l --sort=-v:refname "v2*" | head -n 1) # always checkout the latest release of libtorrent v2
# git checkout "$(git tag -l --sort=-v:refname "v1*" | head -n 1)" # always checkout the latest release of libtorrent v1
git checkout $(git tag -l --sort=-v:refname "v2*" | head -n 1) # always checkout the latest release of libtorrent v2
cmake -Wno-dev -Wno-deprecated -G Ninja -B build \
	-D CMAKE_BUILD_TYPE="Release" \
	-D CMAKE_CXX_STANDARD="17" \
	-D BOOST_INCLUDEDIR="$HOME/boost_${boost_version//./_}/" \
	-D CMAKE_INSTALL_PREFIX="/usr/local"
cmake --build build
cmake --install build
#
git clone --shallow-submodules --recurse-submodules https://github.com/qbittorrent/qBittorrent.git ~/qbittorrent && cd ~/qbittorrent
git checkout "$(git tag -l --sort=-v:refname | head -n 1)" # always checkout the latest release of qbittorrent
cmake -Wno-dev -Wno-deprecated -G Ninja -B build \
	-D CMAKE_BUILD_TYPE="release" \
	-D CMAKE_CXX_STANDARD="17" \
	-D BOOST_INCLUDEDIR="$HOME/boost_${boost_version//./_}/" \
	-D CMAKE_INSTALL_PREFIX="/usr/local"
cmake --build build
cmake --install build
