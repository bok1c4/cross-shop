require "net/http"
require "cross_shop/search_api/response"

module CrossShop
  module SearchApi
    # The real transport: one GET per call over Ruby's standard-library HTTP
    # client. Raises on network errors and timeouts; never retries.
    class NetHttpTransport
      # SearchApi scrapes the target site live, so responses can take a while.
      def initialize(open_timeout: 10, read_timeout: 60)
        @open_timeout = open_timeout
        @read_timeout = read_timeout
      end

      def get(uri, query:, headers:)
        uri = uri.dup
        uri.query = URI.encode_www_form(query)

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
