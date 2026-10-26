require "test_helper"
require "json"
require "cross_shop/stores"

# Runs the converters over every response saved by the SearchApi client.
# Whatever the data looks like, no listing may vanish: each one becomes a
# product or a reject with a reason.
class CachedResponsesTest < Minitest::Test
  ROOT = File.expand_path("../../../fixtures/searchapi/responses", __dir__)

  CrossShop::Stores::BY_ENGINE.each do |engine, store|
    define_method("test_every_#{engine}_listing_is_a_product_or_a_reject") do
      files = Dir[File.join(ROOT, engine, "*.json")]
      skip "no cached #{engine} responses" if files.empty?

      files.each do |file|
        response = JSON.parse(File.read(file, encoding: Encoding::UTF_8))
        conversion = store.convert(response)

        assert_equal response.fetch("organic_results").size, conversion.products.size + conversion.rejects.size, file
        conversion.rejects.each { |reject| refute_empty reject.reason, file }
      end
    end
  end
end
