#!/bin/sh
# package-macos.sh <bindir> <outdir>: builds rdpdiy-host-<version>-macos-<arch>.pkg from the
# rdpdiy-host and service binaries that build-macos.sh writes to <bindir>.
#
# Optional env:
#   RDPDIY_SIGN_APP       "Developer ID Application: …" (default: ad-hoc signature)
#   RDPDIY_SIGN_PKG       "Developer ID Installer: …"   (default: unsigned .pkg)
#   RDPDIY_NOTARY_PROFILE notarytool keychain profile; notarizes and staples the .pkg
set -eu
bin=$1 out=$2
here=$(cd "$(dirname "$0")" && pwd)
mac=$here/macos
version=$(grep -m1 '^version' "$here/../Cargo.toml" | cut -d'"' -f2)
min_macos=${MACOSX_DEPLOYMENT_TARGET:-10.14}
case $(lipo -archs "$bin/rdpdiy-host") in
	arm64) arch=arm64 ;;
	x86_64) arch=x86_64 ;;
	*arm64*x86_64* | *x86_64*arm64*) arch=universal ;;
	*) echo "unexpected architectures in $bin/rdpdiy-host" >&2; exit 1 ;;
esac

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
app=$work/root/Applications/rdpdiy-host.app
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$out"
install -m755 "$bin/rdpdiy-host" "$bin/service" "$app/Contents/MacOS/"
install -m755 "$mac/uninstall.sh" "$app/Contents/Resources/"
install -m644 "$here/../LICENCE" "$app/Contents/Resources/"
sed -e "s/@VERSION@/$version/g" -e "s/@MIN_MACOS@/$min_macos/g" "$mac/Info.plist" > "$app/Contents/Info.plist"

iconset=$work/AppIcon.iconset
mkdir "$iconset"
for s in 16 32 128 256 512; do
	sips -z $s $s "$here/../res/icon.png" --out "$iconset/icon_${s}x${s}.png" >/dev/null
	sips -z $((s * 2)) $((s * 2)) "$here/../res/icon.png" --out "$iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns -o "$app/Contents/Resources/AppIcon.icns" "$iconset"

# Keep quarantine and Finder metadata out of the payload.
xattr -cr "$work/root"
export COPYFILE_DISABLE=1

identity=${RDPDIY_SIGN_APP:--}
if [ "$identity" = - ]; then
	set -- --sign -
else
	set -- --sign "$identity" --options runtime --timestamp --entitlements "$mac/entitlements.plist"
fi
codesign --force "$@" "$app/Contents/MacOS/service"
codesign --force "$@" "$app/Contents/MacOS/rdpdiy-host"
codesign --force "$@" "$app"
codesign --verify --strict --deep "$app"

# Not relocatable: Installer would otherwise "upgrade" any copy of the bundle it finds
# elsewhere on disk instead of /Applications/rdpdiy-host.app, which the launchd plists point at.
pkgbuild --analyze --root "$work/root" "$work/component.plist" >/dev/null
plutil -replace 0.BundleIsRelocatable -bool NO "$work/component.plist"
pkgbuild --root "$work/root" --component-plist "$work/component.plist" \
	--identifier diy.rdp.host --version "$version" --install-location / \
	--scripts "$mac/scripts" "$work/rdpdiy-host.pkg" >/dev/null

sed -e "s/@VERSION@/$version/g" -e "s/@MIN_MACOS@/$min_macos/g" \
	-e "s/@ARCHS@/$( [ $arch = universal ] && echo arm64,x86_64 || echo $arch )/" \
	"$mac/distribution.xml" > "$work/distribution.xml"
cp -R "$mac/resources" "$work/resources"
cp "$here/../LICENCE" "$work/resources/LICENSE.txt"
pkg=$out/rdpdiy-host-$version-macos-$arch.pkg
set --
[ -n "${RDPDIY_SIGN_PKG:-}" ] && set -- --sign "$RDPDIY_SIGN_PKG" --timestamp
productbuild "$@" --distribution "$work/distribution.xml" --resources "$work/resources" \
	--package-path "$work" "$pkg" >/dev/null

if [ -n "${RDPDIY_NOTARY_PROFILE:-}" ]; then
	xcrun notarytool submit "$pkg" --keychain-profile "$RDPDIY_NOTARY_PROFILE" --wait
	xcrun stapler staple "$pkg"
fi
shasum -a 256 "$pkg"
