module CrossShop
  # Field health for one batch of listings (one response or one parsed
  # page): how often each field is filled, and how often its value is
  # plausible. A layout change shows up as a drop in one of the two. An
  # empty batch never passes: zero listings is a signal of its own.
  module FieldHealth
    # read: how to get the value from a listing (default: item[field]).
    # valid: optional plausibility check on filled values.
    Rule = Data.define(:field, :min_filled, :read, :valid, :min_valid) do
      def initialize(field:, min_filled:, read: nil, valid: nil, min_valid: 1.0)
        super(field:, min_filled:, read: read || ->(item) { item[field] }, valid:, min_valid:)
      end
    end

    Report = Data.define(:field, :total, :filled, :valid, :passed, :problem)

    def self.check(items, rules)
      rules.map { |rule| report(items, rule) }
    end

    def self.report(items, rule)
      filled = items.map { |item| rule.read.call(item) }.reject { |value| blank?(value) }
      valid = rule.valid ? filled.count { |value| rule.valid.call(value) } : filled.size

      problem =
        if items.empty?
          "no listings"
        elsif filled.size < rule.min_filled * items.size
          "#{percent(filled.size, items.size)} filled, needs #{percent(rule.min_filled, 1)}"
        elsif valid < rule.min_valid * filled.size
          "#{percent(valid, filled.size)} plausible, needs #{percent(rule.min_valid, 1)}"
        end

      Report.new(field: rule.field, total: items.size, filled: filled.size, valid:, passed: problem.nil?, problem:)
    end

    def self.blank?(value)
      value.nil? || (value.respond_to?(:empty?) && value.empty?) || (value.is_a?(String) && value.strip.empty?)
    end

    def self.percent(part, whole)
      "#{(100.0 * part / whole).round}%"
    end
  end
end
