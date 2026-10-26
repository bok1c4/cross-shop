module CrossShop
  module SearchApi
    # What any transport returns. The client depends only on this shape,
    # so tests can swap the real HTTP transport for a fake one.
    Response = Data.define(:status, :body)
  end
end
