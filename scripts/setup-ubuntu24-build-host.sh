#!/bin/bash
# One-time host setup for offline LEDE builds (Ubuntu 24.04).
# Run with sudo on the build machine: sudo ./scripts/setup-ubuntu24-build-host.sh
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root: sudo $0" >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y \
  ack antlr3 asciidoc autoconf automake autopoint binutils bison build-essential \
  bzip2 ccache cmake cpio curl device-tree-compiler fastjar flex g++ gawk \
  gettext git gperf haveged help2man intltool lib32gcc-s1 libelf-dev \
  libglib2.0-dev libgmp3-dev libltdl-dev libmpc-dev libmpfr-dev libncurses-dev \
  libncurses5-dev libreadline-dev libssl-dev libtool libz-dev lrzsz mkisofs \
  msmtp nano ninja-build patch pkgconf python3 python3-setuptools python3-dev \
  python3-pip qemu-utils rsync scons squashfs-tools subversion \
  swig texinfo unzip wget xxd zlib1g-dev musl-tools clang llvm llvm-dev libllvm-dev libclang-dev

# Lean / PassWall Go builds need a recent host Go when diy-part2 probes go.mod.
if ! command -v go >/dev/null 2>&1; then
  apt-get install -y golang-go || true
fi

echo "Host packages installed."
echo "Suggested: export LEDE_WORK=/workdir/lede-build  (needs ~80–120 GiB free)"
