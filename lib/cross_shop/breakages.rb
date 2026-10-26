require "cross_shop/ebay_parser"
require "cross_shop/searchapi_health"

module CrossShop
  # Simulated eBay layout changes applied to a saved page, and detection by
  # comparing a page's field health with its own baseline. A baseline per
  # page instead of fixed thresholds: Phase 5a showed one bar does not fit
  # every query.
  module Breakages
    Scenario = Data.define(:description, :apply)
    Health = Data.define(:listings, :reports)
    Regression = Data.define(:field, :before, :after)

    ALL = {
      "row_class_renamed" => Scenario.new(
        description: "Attribute rows renamed (s-card__attribute-row to s-card__detail-row)",
        apply: ->(html) { html.gsub("s-card__attribute-row", "s-card__detail-row") }
      ),
      "title_class_renamed" => Scenario.new(
        description: "Title container renamed (s-card__title to s-card__headline)",
        apply: ->(html) { html.gsub("s-card__title", "s-card__headline") }
      ),
      "price_prefix_added" => Scenario.new(
        description: %(Prices shown as "US $99.99" instead of "$99.99"),
        apply: ->(html) { html.gsub(/(<span class="[^"]*s-card__price[^"]*">)\$/, '\1US $') }
      ),
      "card_class_renamed" => Scenario.new(
        description: "Listing cards renamed (li.s-card to li.s-tile)",
        apply: ->(html) { html.gsub(/(<li[^>]* class=")s-card(?=[\s"])/, '\1s-tile') }
      ),
      "price_class_renamed" => Scenario.new(
        description: "Price spans renamed (s-card__price to s-card__amount); the parser does not use the class",
        apply: ->(html) { html.gsub("s-card__price", "s-card__amount") }
      )
    }.freeze

    # A field regresses when its filled or plausible share falls by more than
    # this, or the listing count falls by more than this share.
    TOLERANCE = 0.1

    def self.health(html)
      listings = EbayParser.parse(html)
      Health.new(listings: listings.size, reports: FieldHealth.check(listings, SearchApiHealth::RULES.fetch("ebay_search")))
    end

    def self.regressions(baseline, current, tolerance: TOLERANCE)
      if current.listings < baseline.listings * (1 - tolerance)
        return [Regression.new(field: "listings", before: baseline.listings, after: current.listings)]
      end

      baseline.reports.zip(current.reports).filter_map do |before, after|
        filled = [share(before.filled, before.total), share(after.filled, after.total)]
        plausible = [share(before.valid, before.filled), share(after.valid, after.filled)]
        if filled[0] - filled[1] > tolerance
          Regression.new(field: before.field, before: filled[0].round(2), after: filled[1].round(2))
        elsif plausible[0] - plausible[1] > tolerance
          Regression.new(field: before.field, before: plausible[0].round(2), after: plausible[1].round(2))
        end
      end
    end

    def self.share(part, whole)
      whole.zero? ? 0.0 : part.fdiv(whole)
    end
  end
end
