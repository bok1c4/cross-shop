source "https://rubygems.org"

# Fails `bundle install` loudly if run under the wrong Ruby (mise.toml pins 3.4).
ruby "~> 3.4.0"

# Ruby 3.4 ships csv as a bundled gem, so Bundler needs it listed.
gem "csv"

group :development, :test do
  gem "minitest"
  gem "rake"
  gem "standard"
end
