cask "dynamicnotch" do
  version "1.4.0"
  sha256 :no_check

  url "https://github.com/jackson-storm/DynamicNotch/releases/download/v#{version}/DynamicNotch_v#{version}.dmg"
  name "DynamicNotch"
  desc "Dynamic Notch for macOS"
  homepage "https://github.com/jackson-storm/DynamicNotch"

  livecheck do
    url :url
    strategy :github_latest
  end

  app "DynamicNotch.app"
end
