cask "openshuttler" do
  version "1.0.3"
  sha256 "464e8bddaab31fd9817b3c21fd180b0af76e6327812f4f01f5f080f6a1f2a72c"

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

