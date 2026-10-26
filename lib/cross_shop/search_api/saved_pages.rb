require "fileutils"
require "uri"
require "cross_shop/search_api/client"

module CrossShop
  module SearchApi
    # The store page SearchApi fetched for a search (search_metadata.html_url).
    # Downloading it is free (measured on 2026-10-26 with the Account API).
    # Stored as <root>/<engine>/<search_id>.html and never downloaded twice.
    class SavedPages
      HOST = "www.searchapi.io"
      SEARCH_ID = /\Asearch_[A-Za-z0-9]+\z/
      ENGINE = /\A[a-z0-9_]+\z/

      def initialize(root:, transport:, api_key:)
        @root = root
        @transport = transport
        @api_key = api_key
      end

      def read(engine, response)
        path = path_for(engine, response)
        File.read(path, encoding: Encoding::UTF_8) if File.exist?(path)
      end

      def fetch(engine, response)
        saved = read(engine, response)
        return saved if saved

        uri = URI(response.dig("search_metadata", "html_url").to_s)
        # html_url comes from a response, and the key goes with the request:
        # it is only ever sent to SearchApi itself.
        raise ArgumentError, "refusing to send the API key to #{uri.host.inspect}" unless uri.scheme == "https" && uri.host == HOST

        page = @transport.get(uri.dup, query: {}, headers: {"Authorization" => "Bearer #{@api_key}"})
        raise ApiError, "SearchApi returned #{page.status} for the saved page #{uri.path}" unless page.status == 200

        html = page.body.dup.force_encoding(Encoding::UTF_8)
        raise SecretInResponse, "the saved page contains the API key; not storing it" if html.include?(@api_key)

        path = path_for(engine, response)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, html)
        html
      end

      private

      # Both parts become a file path, so both are checked.
      def path_for(engine, response)
        id = response.dig("search_metadata", "id").to_s
        raise ArgumentError, "unexpected search id #{id.inspect}" unless id.match?(SEARCH_ID)
        raise ArgumentError, "unexpected engine #{engine.inspect}" unless engine.match?(ENGINE)

        File.join(@root, engine, "#{id}.html")
      end
    end
  end
end
