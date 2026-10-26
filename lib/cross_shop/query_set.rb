require "yaml"

module CrossShop
  # config/queries.yml: the engines and queries this project fetches. Every
  # script and the site read it from here, so they agree on what "all" means.
  QuerySet = Data.define(:engines, :queries) do
    def self.load(path = File.expand_path("../../config/queries.yml", __dir__))
      config = YAML.load_file(path)
      new(engines: config.fetch("engines"), queries: config.fetch("queries"))
    end
  end
end
