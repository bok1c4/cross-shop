source "https://rubygems.org"

# Fails `bundle install` loudly if run under the wrong Ruby (mise.toml pins 3.4).
ruby "~> 3.4.0"

# Ruby 3.4 ships csv as a bundled gem, so Bundler needs it listed.
gem "csv"

# Parses eBay's search-result HTML in Phase 3.
gem "nokogiri", "~> 1.18"

# Demo site: Sinatra app served by Puma through rackup; kramdown renders
# LEARNINGS.md; erubi so ERB templates can escape HTML by default.
gem "erubi", "~> 1.13"
gem "kramdown", "~> 2.5"
gem "puma", "~> 8.0"
gem "rackup", "~> 2.3"
gem "sinatra", "~> 4.2"

group :development, :test do
  # Drives headless Chrome over the DevTools Protocol for Phase 4.
  gem "ferrum", "~> 0.20"
  gem "minitest"
  gem "rack-test", "~> 2.3"
  gem "rake"
  gem "standard"
end
