cask "openshuttler" do
  version "1.0.6"
  sha256 "11c7c1b0bcea6c989ad3cba36fc6d4d0001ba135ed70bf89ad013c0619c8cc6f"

  url "https://github.com/alessandrofalls/OpenShuttler/releases/download/v#{version}/OpenShuttler-macOS-arm64.zip"
  name "OpenShuttler"
  desc "Lightweight, native macOS menu bar app for SSH connections"
  homepage "https://github.com/alessandrofalls/OpenShuttler"

  depends_on arch: :arm64
  depends_on macos: :ventura

  app "OpenShuttler.app"

  zap trash: [
    "~/.config/openshuttler",
  ]
end
