# Homebrew formula for vision-ocr. To publish it, copy this file into a tap repository
# (e.g. github.com/ajmc/homebrew-tap as Formula/vision-ocr.rb) and fill in sha256 for the release tarball:
#   curl -sL https://github.com/ajmc/vision-ocr/archive/refs/tags/v0.1.0.tar.gz | shasum -a 256
class VisionOcr < Formula
  desc "OCR images and PDFs from the command line with Apple's Vision framework"
  homepage "https://github.com/ajmc/vision-ocr"
  url "https://github.com/ajmc/vision-ocr/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "REPLACE_WITH_SHA256_OF_RELEASE_TARBALL"
  license "MIT"
  head "https://github.com/ajmc/vision-ocr.git", branch: "main"

  depends_on xcode: ["15.0", :build]
  depends_on :macos
  depends_on macos: :ventura

  def install
    system "swift", "build", "--disable-sandbox", "-c", "release"
    bin.install ".build/release/vision-ocr"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/vision-ocr --version")
    assert_match "en-US", shell_output("#{bin}/vision-ocr --list-languages")
  end
end
