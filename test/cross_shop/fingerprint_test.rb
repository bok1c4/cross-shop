require "test_helper"
require "cross_shop/fingerprint"

class FingerprintTest < Minitest::Test
  # Shape of a tls.peet.ws /api/all response; addresses from the
  # documentation ranges (RFC 5737), values shortened.
  SAMPLE = {
    "ip" => "203.0.113.7:50123",
    "http_version" => "h2",
    "user_agent" => "curl/8.7.1",
    "tls" => {
      "ciphers" => %w[TLS_AES_128_GCM_SHA256 TLS_AES_256_GCM_SHA384],
      "extensions" => [{"name" => "server_name"}, {"name" => "supported_groups"}],
      "ja3_hash" => "375c6162a492dfbf2795909110ce8424",
      "ja4" => "t13d497h2_0d8feac7bc37_7395dae3b2f3",
      "client_random" => "ab12", "session_id" => "cd34"
    },
    "http2" => {"akamai_fingerprint_hash" => "d5fcbdc393757341115a861bf8d23265"},
    "tcpip" => {
      "ip" => {"ttl" => 64, "src_ip" => "203.0.113.7", "dst_ip" => "198.51.100.2"},
      "tcp_syn" => {"src_ip" => "203.0.113.7", "window" => 65535, "mss" => 1460},
      "p0f" => "Mac OS X [generic]"
    },
    "donate" => "Please consider donating"
  }.freeze

  def test_sanitize_removes_every_ip_address_and_per_connection_randomness
    clean = CrossShop::Fingerprint.sanitize(SAMPLE)

    refute_match(/203\.0\.113\.7|198\.51\.100\.2/, JSON.generate(clean))
    refute clean.fetch("tls").key?("client_random")
    refute clean.fetch("tls").key?("session_id")
  end

  def test_sanitize_keeps_the_fingerprints
    clean = CrossShop::Fingerprint.sanitize(SAMPLE)

    assert_equal "t13d497h2_0d8feac7bc37_7395dae3b2f3", clean.dig("tls", "ja4")
    assert_equal 64, clean.dig("tcpip", "ip", "ttl")
    assert_equal "Mac OS X [generic]", clean.dig("tcpip", "p0f")
  end

  # Defence in depth: an address under a key we did not anticipate.
  def test_sanitize_redacts_ip_addresses_in_unexpected_places
    clean = CrossShop::Fingerprint.sanitize(SAMPLE.merge("http1" => {"headers" => ["X-Forwarded-For: 203.0.113.7"]}))

    assert_equal ["X-Forwarded-For: [redacted ip]"], clean.dig("http1", "headers")
  end

  # Found on the first real run: Chrome's four-part version number was
  # redacted as if it were an IP address.
  def test_version_numbers_are_not_mistaken_for_ip_addresses
    agents = [
      "Mozilla/5.0 (Macintosh) AppleWebKit/537.36 HeadlessChrome/143.0.7499.40 Safari/537.36",
      "Mozilla/5.0 (Macintosh) AppleWebKit/537.36 Chrome/143.0.0.0 Safari/537.36"
    ]
    agents.each do |agent|
      assert_equal agent, CrossShop::Fingerprint.sanitize({"user_agent" => agent})["user_agent"]
    end
  end

  def test_summary_row
    row = CrossShop::Fingerprint.summary(SAMPLE)

    assert_equal(
      {http_version: "h2", user_agent: "curl/8.7.1", ja3_hash: "375c6162a492dfbf2795909110ce8424",
       ja4: "t13d497h2_0d8feac7bc37_7395dae3b2f3", http2_hash: "d5fcbdc393757341115a861bf8d23265",
       ciphers: 2, extensions: 2, ttl: 64, tcp_signature: "Mac OS X [generic]"},
      row
    )
  end
end
