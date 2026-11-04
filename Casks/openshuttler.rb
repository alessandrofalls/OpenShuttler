cask "openshuttler" do
  version "1.0.5"
  sha256 "f16478c46b4510218e34e6cfe827438787272bb394b69aef69c92cf1f2f9aade"

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
