cask "openshuttler" do
  version "1.0.2"
  sha256 "6c016501627111ce122fa2a782e8bc0bea56bf9de30d54c0bc5fc236a6a5796f"

  url "https://github.com/alessandrofalls/OpenShuttler/releases/download/v#{version}/OpenShuttler-macOS-arm64.zip"
  name "OpenShuttler"
  desc "Lightweight, native macOS menu bar app for SSH connections"
  homepage "https://github.com/alessandrofalls/OpenShuttler"

  depends_on arch: :arm64
  depends_on macos: ">= :ventura"

  app "OpenShuttler.app"

  zap trash: [
    "~/.config/openshuttler",
  ]
end

