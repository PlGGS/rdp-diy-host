# rdp.diy Host

A headless build of [RustDesk](https://github.com/rustdesk/rustdesk)'s background service. It
lets a computer be controlled from the [rdp.diy](https://rdp.diy) web console, like the host
component of Chrome Remote Desktop. It has no UI or tray icon.

rdp.diy Host is an independent project. It is not affiliated with or endorsed by RustDesk or
Purslane Tech Pte. Ltd. "RustDesk" is their name; this build does not use it as a brand.

## License and modifications (AGPL-3.0 §5)

This is a modified version of RustDesk 1.5.0, licensed under the GNU Affero General Public
License v3.0 like the original (see `LICENCE`). Upstream copyright notices are kept.

Modified by rdp.diy, starting 2026-10-19:

- `src/rdpdiy.rs` (new): sets the app name (`rdpdiy-host`) and org/bundle ID (`diy.rdp.host`),
  fixes the ID, relay and API servers and the server key at build time, defaults to
  password-only sessions, and hides the tray.
- `src/main.rs`, `src/service.rs`, `src/lib.rs`: feature-gated hooks (`--features rdpdiy`) that
  call the above and print usage instead of opening RustDesk's UI.
- `Cargo.toml`: the `rdpdiy` feature; Windows resource and macOS bundle names.
- `res/*.png`, `res/*.ico`: rdp.diy icons replace RustDesk's logos.
- `src/rdpdiy.rs` also forces `allow-auto-update` off (RustDesk's updater would install stock
  RustDesk) and adds `--permissions` on macOS.
- `src/server/connection.rs`: a feature-gated hook that refuses a screen-sharing login with an
  error naming the missing macOS Screen Recording permission, instead of starting a session that
  can never send a frame.
- `src/common.rs`: a feature-gated hook that skips upstream's public STUN probe for the host's
  public IPv6 address, so the host contacts no server but rdp.diy's own.
- `rdpdiy/`, `.github/workflows/rdpdiy-macos.yml`: build and packaging files.

Without `--features rdpdiy` the code builds as stock RustDesk.

## Build

Linux (.deb, built in Docker):

```bash
docker build -f rdpdiy/Dockerfile.linux -o out \
  --build-arg RDPDIY_ID_SERVER=rdp.diy \
  --build-arg RDPDIY_API_SERVER=https://rdp.diy \
  --build-arg RDPDIY_KEY="$(cat id_ed25519.pub)" .
```

macOS (.pkg). Needs Xcode command line tools, rustup and vcpkg with the codec libraries for
each arch (`arm64-osx`, `x64-osx`; run from outside this repo so vcpkg.json isn't used):

```bash
$VCPKG_ROOT/vcpkg install --classic libvpx:arm64-osx libyuv:arm64-osx opus:arm64-osx aom:arm64-osx
RDPDIY_KEY="$(cat id_ed25519.pub)" rdpdiy/build-macos.sh arm64 target/rdpdiy-macos   # or x86_64, universal
rdpdiy/package-macos.sh target/rdpdiy-macos dist
```

Set `RDPDIY_SIGN_APP`, `RDPDIY_SIGN_PKG` and `RDPDIY_NOTARY_PROFILE` to sign with Developer ID and
notarize. Without them the package is ad-hoc signed: fine for `install.sh` (curl doesn't
quarantine downloads), but Gatekeeper blocks it when opened from a browser download, and
TCC permissions reset on every update. `.github/workflows/rdpdiy-macos.yml` builds both
arches and attaches them to the release for a `rdpdiy-<version>` tag.

Windows uses RustDesk's usual toolchain (vcpkg) with `cargo build --release --features rdpdiy`
and the same `RDPDIY_*` variables. Rename the binary to `rdpdiy-host.exe`, because the
service finds its own processes by that name.

## Install (Linux)

```bash
curl -fsSL https://rdp.diy/install.sh | sudo sh -s -- --token <deploy token>
```

The script installs the .deb, which starts the `rdpdiy-host` systemd service. It then runs
`rdpdiy-host --deploy --token …` to enroll the computer in your team.

## Install (macOS)

The same command works on a Mac: it downloads the .pkg for `uname -m` and runs `installer`.
Or open the .pkg, or `brew install --cask plggs/rdpdiy/rdpdiy-host` (cask template in
`rdpdiy/homebrew/`). The package installs `/Applications/rdpdiy-host.app`, a LaunchDaemon
(`diy.rdp.rdpdiy-host_service`, runs `service` as root), a LaunchAgent
(`diy.rdp.rdpdiy-host_server`, runs `rdpdiy-host --server` in each login session and at the
login window) and a `/usr/local/bin/rdpdiy-host` wrapper.

One-click install: **Add a device > Download for Mac** in the console serves the same signed
package as `rdpdiy-host-installer-<token>.pkg`, with a fresh single-use token (valid 1 hour)
that enrolls the Mac for whoever downloaded it. The postinstall reads the token from the
package's own filename (`$1`), runs `--deploy`, and, when opened in Installer.app, asks for
the connection password. Renaming the file to drop the token gives a plain install.

Either way macOS then asks to allow **rdp.diy Host** under Screen & System Audio Recording
and Accessibility. MDM deployments should push a PPPC profile for bundle ID `diy.rdp.host`
instead, and `installer -pkg` installs (MDM, Homebrew, `install.sh`) never show the password
dialog.

Remove with `sudo /Applications/rdpdiy-host.app/Contents/Resources/uninstall.sh` (`--purge`
also deletes the ID and settings).
