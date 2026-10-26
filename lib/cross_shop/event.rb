module CrossShop
  # Something that really happened during a search, as reported by the code
  # that did it. engine is nil for run-level events.
  Event = Data.define(:at, :engine, :kind, :data)
end
