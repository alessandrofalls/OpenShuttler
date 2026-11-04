cask "openshuttler" do
  version "1.0.4"
  sha256 "21381dded90d13b9b6ada47904e96921dd52c0c6f61c273631d40966524b57f5"

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
