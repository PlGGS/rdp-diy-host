#!/bin/sh
# package-deb.sh <binary> <outdir>: builds rdpdiy-host_<version>_<arch>.deb
set -eu
bin=$1 out=$2
here=$(cd "$(dirname "$0")" && pwd)
version=$(grep -m1 '^version' "$here/../Cargo.toml" | cut -d'"' -f2)
arch=$(dpkg --print-architecture)
root=$(mktemp -d)
install -Dm755 "$bin" "$root/usr/bin/rdpdiy-host"
install -Dm644 "$here/debian/rdpdiy-host.service" "$root/usr/lib/systemd/system/rdpdiy-host.service"
install -Dm644 "$here/../LICENCE" "$root/usr/share/doc/rdpdiy-host/copyright"
mkdir -p "$root/DEBIAN"
for s in postinst prerm postrm; do install -m755 "$here/debian/$s" "$root/DEBIAN/$s"; done
cat > "$root/DEBIAN/control" <<CTRL
Package: rdpdiy-host
Version: $version
Architecture: $arch
Maintainer: rdp.diy <support@rdp.diy>
Homepage: https://rdp.diy
Section: net
Priority: optional
Depends: libgtk-3-0, libxcb-randr0, libxdo3, libxfixes3, libxcb-shape0, libxcb-xfixes0, libasound2, libpulse0, libpam0g, libgstreamer1.0-0, libgstreamer-plugins-base1.0-0, libva2, libva-drm2, libva-x11-2, libvpx7, libyuv0, libaom3, libopus0, xdotool
Description: rdp.diy Host - lets this computer be controlled from the rdp.diy web console
 Headless background service, based on RustDesk (AGPL-3.0). Source:
 https://github.com/PlGGS/rdp-diy-host
CTRL
dpkg-deb --root-owner-group --build "$root" "$out/rdpdiy-host_${version}_${arch}.deb"
