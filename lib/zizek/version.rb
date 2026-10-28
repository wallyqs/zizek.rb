# frozen_string_literal: true

module Zizek
  # The gemspec reads this file directly, so it must stay free of requires:
  # loading the rest of the package to learn the version would drag the
  # generated core into every `gem build`.
  VERSION = "0.1.1"
end
