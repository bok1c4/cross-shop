require "cross_shop/product"

module CrossShop
  # Finds listings in different stores that are probably the same product.
  #
  # Tier "style_code": both titles contain the same manufacturer style code
  # (JH5633, DD1391-100). Strong evidence on its own, whatever the prices.
  # Tier "title": the same known brand, title-word overlap (Jaccard) of at
  # least 0.5, and lowest prices within a factor of 1.5. Weaker; the labelled
  # sample measures how often it is right.
  module Matcher
    Candidate = Data.define(:a, :b, :tier, :score, :evidence)

    MIN_TITLE_SIMILARITY = 0.5
    MAX_PRICE_RATIO = 1.5

    # Words that say nothing about which product a listing is.
    STOPWORDS = Set.new(%w[
      a an and the for with of in on by new
      men mens women womens unisex kids size sizes us uk eu
      shoe shoes sneaker sneakers trainers
    ])

    # Tokens of six or more characters mixing letters and digits, optionally
    # with one hyphen: JH5633, DD1391-100, BB550WT1, 162050C. Six keeps out
    # sizes and model families such as "4XL" or "BB550".
    def self.style_codes(title)
      tokens = title.upcase.scan(/[A-Z0-9]+(?:-[A-Z0-9]+)?/)
      tokens.select { |token| token.length >= 6 && token.match?(/[A-Z]/) && token.match?(/\d/) }.uniq
    end

    def self.title_words(title)
      words = title.downcase.delete("'’").scan(/[a-z0-9]+/)
      Set.new(words.reject { |word| word.length < 2 || STOPWORDS.include?(word) })
    end

    # Jaccard similarity: shared words / all words.
    def self.similarity(a, b)
      words_a = title_words(a.title)
      words_b = title_words(b.title)
      return 0.0 if words_a.empty? || words_b.empty?

      (words_a & words_b).size.fdiv((words_a | words_b).size)
    end

    def self.candidates(products)
      products.combination(2).filter_map { |a, b| match(a, b) unless a.store == b.store }
    end

    def self.match(a, b)
      shared = style_codes(a.title) & style_codes(b.title)
      return Candidate.new(a:, b:, tier: "style_code", score: 1.0, evidence: shared.first) if shared.any?
      return nil if a.brand.nil? || a.brand != b.brand

      low, high = [a.price_min, b.price_min].minmax
      return nil if high / low > MAX_PRICE_RATIO

      score = similarity(a, b)
      return nil if score < MIN_TITLE_SIMILARITY

      Candidate.new(a:, b:, tier: "title", score: score.round(2), evidence: "same brand, #{(score * 100).round}% shared words")
    end

    # Amazon titles are the cleanest, so Amazon listings anchor the groups.
    ANCHOR_STORE = "amazon"
    # A style-code match always beats a title match; within a tier, the score decides.
    TIER_WEIGHT = {"style_code" => 2.0, "title" => 0.0}.freeze

    # Each listing from another store joins its single best Amazon match.
    # Following every chain instead (A~B, B~C puts A with C) merged 33 adidas
    # listings into one group on real data. Unmatched listings are groups of one.
    def self.groups(products, candidates = candidates(products))
      attached = best_matches(candidates).transform_values { |candidate| anchor_and_other(candidate).first }
      products.reject { |product| attached.key?(product) }.map do |product|
        [product, *attached.select { |_other, anchor| anchor == product }.keys]
      end
    end

    # For each non-Amazon listing, the candidate pairing it with its best
    # Amazon match: {listing => candidate}. These are the pairs the groups
    # are built from, so they are the pairs to label.
    def self.best_matches(candidates)
      best = {}
      candidates.each do |candidate|
        anchor, other = anchor_and_other(candidate)
        next if anchor.nil?

        best[other] = candidate if best[other].nil? || weight(candidate) > weight(best[other])
      end
      best
    end

    def self.weight(candidate)
      TIER_WEIGHT.fetch(candidate.tier) + candidate.score
    end

    def self.anchor_and_other(candidate)
      a_anchor = candidate.a.store == ANCHOR_STORE
      b_anchor = candidate.b.store == ANCHOR_STORE
      if a_anchor && !b_anchor
        [candidate.a, candidate.b]
      elsif b_anchor && !a_anchor
        [candidate.b, candidate.a]
      end
    end
  end
end
