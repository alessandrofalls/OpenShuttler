cask "openshuttler" do
  version "1.0.4"
  sha256 "6c6211e84b448e866d781ee05d92e9bca57cbf4e11c0c48fa941a64981673bac"

  url "https://github.com/alessandrofalls/OpenShuttler/releases/download/v#{version}/OpenShuttler-macOS-arm64.zip"
  name "OpenShuttler"
  desc "Lightweight, native macOS menu bar app for SSH connections"
  homepage "https://github.com/alessandrofalls/OpenShuttler"

  depends_on arch: :arm64
  depends_on macos: :ventura

  app "OpenShuttler.app"

  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-d", "-r", "com.apple.quarantine", "#{appdir}/OpenShuttler.app"],
                   sudo: false
  end

  zap trash: [
    "~/.config/openshuttler",
  ]
end

