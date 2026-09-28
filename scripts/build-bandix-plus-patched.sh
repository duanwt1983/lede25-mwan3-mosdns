#!/bin/bash
# Build bandix-plus v0.1.2 with count-forwarded-only.patch (host musl binary).
# Output: single executable path (first argument).
set -euo pipefail

OUT="${1:?usage: $0 /path/to/bandix-plus}"
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
PATCH="$ROOT/patches/bandix-plus/count-forwarded-only.patch"
PKG_HASH="ae1179018a709b46455c551c46a2b6ffc458aad2f276999c82f13e2a569362f3"
TARBALL_URL="https://github.com/timsaya/bandix-plus/archive/refs/tags/v0.1.2.tar.gz"
TARGET="x86_64-unknown-linux-musl"
WORK="${TMPDIR:-/tmp}/bandix-plus-patched-$$"
CARGO_HOME="${CARGO_HOME:-$HOME/.cargo}"
RUSTUP_HOME="${RUSTUP_HOME:-$HOME/.rustup}"

cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

mkdir -p "$WORK" "$(dirname "$OUT")"

ensure_rust() {
	export PATH="$CARGO_HOME/bin:$PATH"
	if ! command -v rustup >/dev/null 2>&1; then
		echo "Installing rustup (required for bandix-plus eBPF build)..."
		curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable
		export PATH="$CARGO_HOME/bin:$PATH"
	fi
	rustup toolchain install stable nightly >/dev/null
	rustup target add "$TARGET" --toolchain stable >/dev/null
	if ! command -v bpf-linker >/dev/null 2>&1 && [ ! -x "$CARGO_HOME/bin/bpf-linker" ]; then
		echo "Installing bpf-linker (nightly)..."
		cargo +nightly install bpf-linker --locked 2>/dev/null || cargo +nightly install bpf-linker
	fi
	export PATH="$CARGO_HOME/bin:$PATH"
}

ensure_musl_linker() {
	if command -v musl-gcc >/dev/null 2>&1; then
		export CARGO_TARGET_X86_64_UNKNOWN_LINUX_MUSL_LINKER=musl-gcc
		return 0
	fi
	echo "ERROR: musl-gcc not found (install musl-tools: apt install musl-tools)" >&2
	exit 1
}

fetch_src() {
	local dl="$WORK/v0.1.2.tar.gz"
	if [ ! -f "$dl" ]; then
		curl -fsSL -o "$dl" "$TARBALL_URL"
	fi
	local got
	got=$(sha256sum "$dl" | awk '{print $1}')
	if [ "$got" != "$PKG_HASH" ]; then
		echo "ERROR: bandix-plus source checksum mismatch (got $got)" >&2
		exit 1
	fi
	rm -rf "$WORK/src"
	mkdir -p "$WORK/src"
	tar -xzf "$dl" -C "$WORK/src" --strip-components=1
	patch -d "$WORK/src" -p1 < "$PATCH"
}

build_bin() {
	cd "$WORK/src"
	export PATH="$CARGO_HOME/bin:$PATH"
	if cargo build -q --release --target "$TARGET" -p bandix-plus; then
		:
	elif cargo +nightly build -q --release --target "$TARGET" -p bandix-plus; then
		:
	else
		echo "ERROR: cargo build failed for patched bandix-plus" >&2
		exit 1
	fi
	local bin="$WORK/src/target/$TARGET/release/bandix-plus"
	[ -f "$bin" ] || { echo "ERROR: missing $bin" >&2; exit 1; }
	install -D -m 0755 "$bin" "$OUT"
	echo "bandix-plus: patched host build -> $OUT ($(md5sum "$OUT" | awk '{print $1}'))"
}

ensure_rust
ensure_musl_linker
fetch_src
build_bin
