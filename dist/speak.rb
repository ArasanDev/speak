# dist/speak.rb — Homebrew formula for speak (build-from-source, custom tap).
#
# Unlike speak.cask.rb (P11-b, requires Developer ID + notarization), this
# formula builds on the user's machine — no Gatekeeper check, no cert needed.
# Gatekeeper only inspects downloaded binaries; source builds are exempt.
#
# Setup (once the custom tap exists):
#   brew tap speak-dev/speak https://github.com/speak-dev/homebrew-speak
#   brew install speak
#
# Or test locally from a clone:
#   brew install --build-from-source dist/speak.rb
#
# Requirements:
#   • macOS 26 (Tahoe) + Apple Silicon — SpeechAnalyzer + Foundation Models
#     are macOS 26-only; the build target is arm64-apple-macosx26.0.
#   • Full Xcode 26+ (not just Command Line Tools) — xcodebuild, SpeechAnalyzer,
#     and Foundation Models all require the full Xcode installation.
#   • xcodegen (installed automatically as a build dependency below).
#
# UPDATE before first real tag:
#   1. Create a GitHub release tag (e.g. v0.0.1).
#   2. Replace url + sha256 with the real tarball URL and checksum:
#        curl -L <url> | shasum -a 256
#   3. Run `brew style dist/speak.rb` to verify Homebrew conventions.

class Speak < Formula
  desc "Local-first, free, open-source AI voice dictation for macOS"
  homepage "https://github.com/yourusername/speak"

  # PLACEHOLDER — update url + sha256 once the first GitHub Release tag exists.
  url "https://github.com/yourusername/speak/archive/refs/tags/v0.0.1.tar.gz"
  sha256 "PLACEHOLDER_SHA256_UPDATE_ON_FIRST_TAG"

  license "MIT"

  # Apple Silicon only — SpeechAnalyzer + Foundation Models are arm64 frameworks.
  on_intel do
    disable! level: :cannot_install, because: "speak requires Apple Silicon (arm64)"
  end

  # xcodegen regenerates Speak.xcodeproj from project.yml at build time.
  depends_on "xcodegen" => :build

  # Full Xcode 26+ must be installed by the user; xcode-select alone is not enough.
  depends_on :xcode => "26.0"

  def install
    # Build the Release configuration. CONFIG=Release overrides the Makefile default
    # (Debug) so the installed binary is optimised and correctly strips assertions.
    system "make", "build", "CONFIG=Release"

    # Install Speak.app into the Homebrew cellar under Applications/.
    # `cp -r` into /Applications/ is not permitted in the Homebrew sandbox;
    # see the caveats below for how to make Speak visible in Spotlight/Dock.
    app_src = "build/DerivedData/Build/Products/Release/Speak.app"
    (prefix/"Applications").mkpath
    cp_r app_src, "#{prefix}/Applications/Speak.app"
  end

  def caveats
    <<~EOS
      Speak.app is installed at:
        #{opt_prefix}/Applications/Speak.app

      To make it available in Spotlight and the Dock, copy it to /Applications/:
        cp -r "#{opt_prefix}/Applications/Speak.app" /Applications/

      For Accessibility / Microphone permission grants to survive future brew
      upgrades, run once from the speak source directory:
        make dev-cert

      On first launch, speak will prompt for Microphone + Accessibility permissions.
      All transcription runs on-device — no audio ever leaves your Mac.
    EOS
  end

  test do
    # Verify the app bundle exists with a runnable binary (no display required).
    assert_predicate opt_prefix/"Applications/Speak.app/Contents/MacOS/Speak",
      :executable?
  end
end
