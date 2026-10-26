require "test_helper"

# The repo is public. Saved pages come from other people's websites and can
# carry data about people: the address a page was fetched from, or a seller's
# name and feedback score. Fixtures keep only what the parsers read
# (bin/trim-fixtures), and these tests fail if such data is committed again.
class PublicFixturesTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  FILES = Dir[File.join(ROOT, "{fixtures,data}", "**", "*")].select { |path| File.file?(path) }.freeze

  # A dotted quad without leading zeros that is not part of a longer token,
  # so version numbers (Chrome/158.0.0.0) and SVG path data do not count.
  OCTET = /(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)/
  IPV4 = /(?<![\w.\/-])(?:#{OCTET}\.){3}#{OCTET}(?![\w.])/
  # Private ranges (RFC 1918), loopback, and the documentation ranges (RFC 5737).
  HARMLESS = /\A(?:0|10|127|192\.168|172\.(?:1[6-9]|2\d|3[01])|192\.0\.2|198\.51\.100|203\.0\.113)\./
  # An eBay seller as a search page shows one: "name (6,167) 100%".
  SELLER = /\S+ \(\d[\d,]*\) \d{1,3}(?:\.\d)?%/

  def test_no_fixture_contains_an_ip_address
    found = FILES.flat_map { |path| matches(path, IPV4).reject { |ip| ip.match?(HARMLESS) } }

    assert_empty found
  end

  def test_no_fixture_names_an_ebay_seller
    found = FILES.flat_map { |path| matches(path, SELLER) }

    assert_empty found
  end

  def test_the_patterns_catch_what_they_are_for
    assert_match IPV4, %("ip":"203.0.113.56")
    refute_match IPV4, "HeadlessChrome/158.0.0.0"
    refute_match IPV4, "L2.87.44.5 2.86l13.08"
    assert_match SELLER, "shoe_seller_42 (6,167) 100%"
  end

  private

  def matches(path, pattern)
    File.binread(path).scan(pattern).map { |match| "#{path.delete_prefix("#{ROOT}/")}: #{match}" }
  end
end
