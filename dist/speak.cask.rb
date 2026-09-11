# dist/speak.cask.rb — Homebrew Cask formula for speak.
#
# Cask Cookbook: https://docs.brew.sh/Cask-Cookbook
#
# INERT until docs/roadmap.md P11-b (Developer ID sign + notarize + Homebrew
# Cask) lands. This scaffold cannot be published or meaningfully installed
# today: there is no Developer ID Application cert, so `make release` has
# never produced a real signed+notarized Speak.dmg, and the sha256/url below
# are placeholders, not a real artifact checksum. v0 does not require P11-b —
# it ships as a build-from-source preview via dist/speak.rb (P11-a). Fill in
# the real version/url/sha256 only once a genuine Developer ID release exists.
#
# PLACEHOLDER VALUES — update sha256 and url after `make release`:
#   shasum -a 256 build/release/Speak.dmg
#
# To test locally before publishing:
#   brew install --cask dist/speak.cask.rb
#
# To publish, copy this file to the homebrew-cask tap repository and open a PR.
# The tap path is typically:
#   https://github.com/Homebrew/homebrew-cask/blob/master/Casks/s/speak.rb

cask "speak" do
  version "0.0.1"
  sha256 "ad8ad3e6486af076602bb7211b8e3b66b9cea0456b8c2c7fc6ba49fb90b96a65"

  url "https://github.com/ArasanDev/speak/releases/download/v#{version}/Speak.dmg"
  name "speak"
  desc "Local-first, free, open-source AI voice dictation for macOS"
  homepage "https://github.com/ArasanDev/speak"

  # macOS 26 (Tahoe) minimum on Apple Silicon
  depends_on macos: ">= :tahoe"
  depends_on arch: :arm64

  app "Speak.app"

  # Post-install: inform the user about the two macOS permissions
  caveats <<~EOS
    speak requires two permissions before it can transcribe:
      • Microphone    — for on-device audio capture
      • Accessibility — to detect the hotkey globally and insert text

    On first launch, speak will guide you to grant each permission.
    All transcription and AI neat-writing run 100% locally on Apple Silicon.
  EOS

  zap trash: [
    "~/Library/Application Support/speak",
    "~/Library/Preferences/com.speak.app.plist",
    "~/Library/Saved Application State/com.speak.app.savedState",
    "~/Library/Logs/speak",
  ]
end
