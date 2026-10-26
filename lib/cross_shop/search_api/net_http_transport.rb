require "net/http"
require "cross_shop/search_api/response"

module CrossShop
  module SearchApi
    # The real transport: one GET per call over Ruby's standard-library HTTP
    # client. Raises on network errors and timeouts; never retries.
    class NetHttpTransport
      # SearchApi scrapes the target site live, so responses can take a while,
      # and it gives up on Shein after about 90 s (every one of its 503s came
      # between 90.4 and 90.9 s). Waiting longer lets us read its answer.
      READ_TIMEOUT = 120

      attr_reader :read_timeout

      def initialize(open_timeout: 10, read_timeout: READ_TIMEOUT)
        @open_timeout = open_timeout
        @read_timeout = read_timeout
      end

      def get(uri, query:, headers:)
        uri = uri.dup
        uri.query = URI.encode_www_form(query) unless query.empty?

        # max_retries: 0 because Net::HTTP otherwise resends a GET once after a
        # read timeout, and each SearchApi request may be billed.
        options = {use_ssl: uri.scheme == "https", open_timeout: @open_timeout, read_timeout: @read_timeout, max_retries: 0}
        Net::HTTP.start(uri.host, uri.port, **options) do |http|
          response = http.get(uri.request_uri, headers)
          Response.new(status: response.code.to_i, body: response.body.to_s)
        end
      end
    end
  end
end
