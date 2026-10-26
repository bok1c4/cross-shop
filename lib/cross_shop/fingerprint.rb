require "json"

module CrossShop
  # Responses from tls.peet.ws/api/all: how a client looks to a server at
  # the TLS, HTTP/2 and TCP levels.
  module Fingerprint
    # Keys holding addresses or per-connection randomness. Addresses are
    # personal data and never saved; the randomness is noise.
    DROPPED_KEYS = %w[ip src_ip dst_ip client_random session_id donate].freeze
    # Four octets of 0-255, not part of a longer dotted number, and not right
    # after "/": "Chrome/143.0.0.0" is a version, not an address.
    OCTET = /(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)/
    IPV4 = %r{(?<![\d./])#{OCTET}(?:\.#{OCTET}){3}(?![\d.])}

    # A deep copy without DROPPED_KEYS (except where "ip" holds a hash of
    # fingerprint fields such as the TTL), and with any IPv4 address left in
    # a string replaced.
    def self.sanitize(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, inner), clean|
          next if DROPPED_KEYS.include?(key) && !inner.is_a?(Hash)

          clean[key] = sanitize(inner)
        end
      when Array then value.map { |inner| sanitize(inner) }
      when String then value.gsub(IPV4, "[redacted ip]")
      else value
      end
    end

    def self.summary(response)
      {
        http_version: response["http_version"],
        user_agent: response["user_agent"],
        ja3_hash: response.dig("tls", "ja3_hash"),
        ja4: response.dig("tls", "ja4"),
        http2_hash: response.dig("http2", "akamai_fingerprint_hash"),
        ciphers: response.dig("tls", "ciphers")&.size,
        extensions: response.dig("tls", "extensions")&.size,
        ttl: response.dig("tcpip", "ip", "ttl"),
        # p0f-style signature of the TCP SYN: window, options and their
        # order, which come from the operating system, not the HTTP client.
        tcp_signature: response.dig("tcpip", "p0f")
      }
    end
  end
end
