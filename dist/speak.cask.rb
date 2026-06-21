# dist/speak.cask.rb — Homebrew Cask formula for speak.
#
# Cask Cookbook: https://docs.brew.sh/Cask-Cookbook
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
  sha256 "PLACEHOLDER_SHA256_REPLACE_AFTER_MAKE_RELEASE"

  url "https://github.com/yourusername/speak/releases/download/v#{version}/Speak.dmg"
  name "speak"
  desc "Local-first, free, open-source AI voice dictation for macOS"
  homepage "https://github.com/yourusername/speak"

  # macOS 26 (Tahoe) minimum — speak requires SpeechAnalyzer + Foundation Models,
  # both macOS 26-only. :tahoe == "26" [verified: Homebrew macos_version.rb].
  depends_on macos: ">= :tahoe"

  app "Speak.app"

  # Post-install: open System Preferences so the user can grant required permissions
  # (Accessibility + Input Monitoring + Microphone). speak prompts for these on
  # first launch, so this caveats block is informational only.
  caveats <<~EOS
    speak requires three permissions before it can transcribe:
      • Microphone     — for audio capture
      • Accessibility  — to detect the hotkey while other apps have focus
      • Input Monitoring — to monitor the Fn key globally

    On first launch, speak will walk you through granting each one.

    Note: speak runs 100% on-device. No audio ever leaves your Mac.
  EOS

  zap trash: [
    "~/Library/Application Support/speak",
    "~/Library/Preferences/com.speak.app.plist",
    "~/Library/Saved Application State/com.speak.app.savedState",
    "~/Library/Logs/speak",
  ]
end
