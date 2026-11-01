# Homebrew cask for rdp.diy Host. Lives in the tap repo github.com/PlGGS/homebrew-rdpdiy as
# Casks/rdpdiy-host.rb:  brew install --cask plggs/rdpdiy/rdpdiy-host
# Bump with: brew bump-cask-pr --version <version> plggs/rdpdiy/rdpdiy-host
cask "rdpdiy-host" do
  arch arm: "arm64", intel: "x86_64"

  version "1.5.1"
  sha256 arm:   "0000000000000000000000000000000000000000000000000000000000000000",
         intel: "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/PlGGS/rdp-diy-host/releases/download/rdpdiy-#{version}/rdpdiy-host-#{version}-macos-#{arch}.pkg",
      verified: "github.com/PlGGS/rdp-diy-host/"
  name "rdp.diy Host"
  desc "Background service that lets the rdp.diy web console control this Mac"
  homepage "https://rdp.diy/"

  livecheck do
    url :url
    regex(/^rdpdiy[._-]v?(\d+(?:\.\d+)+)$/i)
    strategy :github_latest
  end

  depends_on macos: ">= :mojave"

  pkg "rdpdiy-host-#{version}-macos-#{arch}.pkg"

  uninstall launchctl: [
              "diy.rdp.rdpdiy-host_server",
              "diy.rdp.rdpdiy-host_service",
            ],
            quit:      "diy.rdp.host",
            pkgutil:   "diy.rdp.host",
            delete:    [
              "/Library/LaunchAgents/diy.rdp.rdpdiy-host_server.plist",
              "/Library/LaunchDaemons/diy.rdp.rdpdiy-host_service.plist",
              "/usr/local/bin/rdpdiy-host",
            ]

  zap trash: [
    "/var/log/rdpdiy-host_service.err",
    "/var/log/rdpdiy-host_service.out",
    "/var/root/Library/Logs/rdpdiy-host",
    "/var/root/Library/Preferences/diy.rdp.rdpdiy-host",
    "~/Library/Logs/rdpdiy-host",
    "~/Library/Preferences/diy.rdp.rdpdiy-host",
  ]

  caveats <<~EOS
    Allow rdp.diy Host in System Settings > Privacy & Security under
    Screen & System Audio Recording and Accessibility, then enroll this Mac:
      sudo rdpdiy-host --deploy --token <deploy token>
      sudo rdpdiy-host --password '<password>'
  EOS
end
