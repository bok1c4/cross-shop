require "digest"
require "fileutils"
require "json"

module CrossShop
  module SearchApi
    # Raw SearchApi response bodies on disk, one file per distinct request.
    # Files are committed, so tests and later phases run offline and no
    # request is ever paid for twice.
    class ResponseCache
      # Engine names become directory names and can come from the command line,
      # so only plain names reach the file system. \A and \z, not ^ and $: in
      # Ruby those match at every line break.
      ENGINE_NAME = /\A[a-z0-9_]+\z/

      def initialize(root)
        @root = root
      end

      # JSON is UTF-8 by definition, so say so instead of trusting the locale:
      # without LANG set, Ruby would read these files as US-ASCII.
      def read(engine, params)
        path = path_for(engine, params)
        File.read(path, encoding: Encoding::UTF_8) if File.exist?(path)
      end

      def write(engine, params, body)
        path = path_for(engine, params)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, body)
        path
      end

      def path_for(engine, params)
        unless ENGINE_NAME.match?(engine)
          raise ArgumentError, "engine must be lowercase letters, digits and underscores, got #{engine.inspect}"
        end

        File.join(@root, engine, "#{slug(params)}-#{digest(engine, params)}.json")
      end

      private

      # Every param is part of the key. Query strings carry only strings, so
      # `page: 2` and `"page" => "2"` are the same request and the same file.
      def digest(engine, params)
        canonical = params.to_h { |key, value| [key.to_s, value.to_s] }.sort
        Digest::SHA256.hexdigest(JSON.generate([engine, canonical]))[0, 16]
      end

      # Readable prefix only; uniqueness comes from the digest.
      def slug(params)
        query = params[:q] || params["q"] || "no-query"
        query.to_s.downcase.gsub(/[^a-z0-9]+/, "-").delete_prefix("-").delete_suffix("-")[0, 40]
      end
    end
  end
end
