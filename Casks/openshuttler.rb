cask "openshuttler" do
  version "1.0.3"
  sha256 "ec50d7cee956ad82ccfeb65ae0ffca733b27b20410db0bc14aaf07ff6ef9b3ac"

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

