#!/bin/sh
# build-macos.sh [arm64|x86_64|universal] <outdir>: builds rdpdiy-host and service for macOS.
# Needs VCPKG_ROOT with libvpx libyuv opus aom installed for each arch's triplet
# (arm64-osx, x64-osx), plus the RDPDIY_* build env (see src/rdpdiy.rs).
set -eu
arch=${1:-$(uname -m)}
out=${2:-target/rdpdiy-macos}
here=$(cd "$(dirname "$0")" && pwd)
cd "$here/.."
: "${VCPKG_ROOT:?set VCPKG_ROOT}"
export MACOSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET:-10.14}
toolchain=${RDPDIY_RUST_TOOLCHAIN:-1.81}
PATH=$(dirname "$(rustup which --toolchain "$toolchain" cargo)"):$PATH

case $arch in
	universal) archs="arm64 x86_64" ;;
	arm64 | x86_64) archs=$arch ;;
	*) echo "unknown arch: $arch" >&2; exit 2 ;;
esac

mkdir -p "$out"
for a in $archs; do
	case $a in
		arm64) target=aarch64-apple-darwin ;;
		x86_64) target=x86_64-apple-darwin ;;
	esac
	rustup target add --toolchain "$toolchain" "$target" >/dev/null
	cargo build --release --features rdpdiy --target "$target" --bin rustdesk --bin service
done

for bin in rustdesk service; do
	name=$bin
	[ "$bin" = rustdesk ] && name=rdpdiy-host
	set --
	for a in $archs; do
		case $a in
			arm64) set -- "$@" "target/aarch64-apple-darwin/release/$bin" ;;
			x86_64) set -- "$@" "target/x86_64-apple-darwin/release/$bin" ;;
		esac
	done
	lipo -create "$@" -output "$out/$name"
	strip -x "$out/$name"
done
echo "$out/rdpdiy-host $out/service ($arch)"
