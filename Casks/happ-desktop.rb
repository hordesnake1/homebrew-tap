cask "happ-desktop" do
  version "4.1.3"
  sha256 :no_check

  url "https://github.com/Happ-proxy/happ-desktop/releases/download/#{version}/Happ.macOS.universal.dmg"
  name "Happ Desktop"
  desc "Desktop client for Happ proxy"
  homepage "https://github.com/Happ-proxy/happ-desktop"

  livecheck do
    url "https://api.github.com/repos/Happ-proxy/happ-desktop/releases"
    strategy :json do |json|
      json.map do |release|
        next if release["draft"]

        release["tag_name"]&.delete_prefix("v")
      end
    end
  end

  app "Happ.app"
end
