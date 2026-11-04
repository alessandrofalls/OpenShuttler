cask "openshuttler" do
  version "1.0.5"
  sha256 "a18cc18d2398b048df933b0d5e713a0acff9bfec53f75beca11e9bbee858e4da"

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
