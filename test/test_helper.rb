require "minitest/autorun"

# Tests run with -w so our own code stays warning-free. Warnings raised
# inside installed gems (kramdown 2.5.2 has one) are not ours to fix, so
# they are dropped; warnings from this project still print.
module GemWarningFilter
  def warn(message, category: nil, **)
    return if message.include?("/gems/")

    super
  end
end
Warning.singleton_class.prepend(GemWarningFilter)
