#!/bin/sh
# Build bandix-plus from patched source inside the OpenWrt build (PKG_BUILD_DIR).
set -eu

build_dir="$1"
output="$2"
target="$3"
linker="$4"
staging_host="${5:-}"

cd "$build_dir"

cargo=""
if [ -n "$staging_host" ] && [ -x "$staging_host/bin/cargo" ]; then
	cargo="$staging_host/bin/cargo"
elif command -v cargo >/dev/null 2>&1; then
	cargo="cargo"
fi

if [ -z "$cargo" ]; then
	echo "ERROR: cargo not found (install rust/host via PKG_BUILD_DEPENDS:=rust/host)" >&2
	exit 1
fi

case "$target" in
	x86_64-unknown-linux-musl)
		export CARGO_TARGET_X86_64_UNKNOWN_LINUX_MUSL_LINKER="$linker"
		;;
	aarch64-unknown-linux-musl)
		export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_MUSL_LINKER="$linker"
		;;
	armv7-unknown-linux-musleabihf)
		export CARGO_TARGET_ARMV7_UNKNOWN_LINUX_MUSLEABIHF_LINKER="$linker"
		;;
	armv7-unknown-linux-musleabi)
		export CARGO_TARGET_ARMV7_UNKNOWN_LINUX_MUSLEABI_LINKER="$linker"
		;;
	armv5te-unknown-linux-musleabi)
		export CARGO_TARGET_ARMV5TE_UNKNOWN_LINUX_MUSLEABI_LINKER="$linker"
		;;
	arm-unknown-linux-musleabi)
		export CARGO_TARGET_ARM_UNKNOWN_LINUX_MUSLEABI_LINKER="$linker"
		;;
	arm-unknown-linux-musleabihf)
		export CARGO_TARGET_ARM_UNKNOWN_LINUX_MUSLEABIHF_LINKER="$linker"
		;;
	riscv64gc-unknown-linux-musl)
		export CARGO_TARGET_RISCV64GC_UNKNOWN_LINUX_MUSL_LINKER="$linker"
		;;
	powerpc64le-unknown-linux-musl)
		export CARGO_TARGET_POWERPC64LE_UNKNOWN_LINUX_MUSL_LINKER="$linker"
		;;
	mips-unknown-linux-musl)
		export CARGO_TARGET_MIPS_UNKNOWN_LINUX_MUSL_LINKER="$linker"
		;;
	mipsel-unknown-linux-musl)
		export CARGO_TARGET_MIPSEL_UNKNOWN_LINUX_MUSL_LINKER="$linker"
		;;
	*)
		echo "ERROR: unsupported Rust target for bandix-plus LEDE build: $target" >&2
		exit 1
		;;
esac

# aya-build may pull nightly for eBPF; stable host toolchain is enough to invoke cargo.
if "$cargo" build -q --release --target "$target" -p bandix-plus; then
	:
elif "$cargo" +nightly build -q --release --target "$target" -p bandix-plus; then
	:
else
	echo "ERROR: cargo build failed for bandix-plus (target $target)" >&2
	exit 1
fi

bin="target/$target/release/bandix-plus"
[ -f "$bin" ] || {
	echo "ERROR: missing $bin after cargo build" >&2
	exit 1
}

install -D -m 0755 "$bin" "$output"
