# Template for the cask in the chiranjeebhub/homebrew-clipstack tap. scripts/release-direct.sh fills
# in the version and checksum and pushes it there.
cask "clipstack" do
  version "@VERSION@"
  sha256 "@SHA256@"

  url "https://github.com/chiranjeebhub/clipstack-site/releases/download/v#{version}/Clipstack-#{version}.dmg",
      verified: "github.com/chiranjeebhub/clipstack-site/"
  name "Clipstack"
  desc "Clipboard history you can search and paste from the keyboard"
  homepage "https://chiranjeebhub.github.io/clipstack-site/support"

  livecheck do
    url "https://chiranjeebhub.github.io/clipstack-site/appcast.xml"
    strategy :sparkle, &:short_version
  end

  auto_updates true
  depends_on macos: ">= :sonoma"

  app "Clipstack.app"

  zap trash: [
    "~/Library/Application Scripts/com.chiranjeebhub.clipstack",
    "~/Library/Containers/com.chiranjeebhub.clipstack",
  ]
end
