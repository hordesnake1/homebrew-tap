cask "notepad-plus-plus-macos" do
  version "1.0.5"
  sha256 :no_check

  url "https://github.com/notepad-plus-plus-mac/notepad-plus-plus-macos/releases/download/v#{version}/Notepad++v#{version}.dmg"
  name "Notepad++ for macOS"
  desc "Notepad++ distribution for macOS"
  homepage "https://github.com/notepad-plus-plus-mac/notepad-plus-plus-macos"

  livecheck do
    url :url
    strategy :github_latest
  end

  app "Notepad++.app"
end
