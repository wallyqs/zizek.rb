# frozen_string_literal: true

require_relative "lib/zizek/version"

Gem::Specification.new do |spec|
  spec.name = "zizek"
  spec.version = Zizek::VERSION
  spec.license = "Apache-2.0"
  spec.authors = ["Waldemar Quevedo"]

  spec.summary = "Property-based testing with portable, cross-language reproduce blobs"
  spec.description = <<~TEXT
    Zizek is a native property-based testing for Ruby, modeled on Hegel and Hypothesis.
    It explores generated examples, records every choice, shrinks the first failure to a
    minimal counterexample, and reports a reproduce blob that replays that exact example.
  TEXT

  spec.homepage = "https://github.com/wallyqs/zizek.rb"
  spec.metadata = {
    "homepage_uri" => "https://github.com/wallyqs/zizek.rb",
    # The gem's file paths are the mirror's paths: the mirror is a subtree
    # split of packages/ruby, so a line number in the gem is a line number
    # there.
    "source_code_uri" => "https://github.com/wallyqs/zizek.rb",
    "changelog_uri" => "https://github.com/wallyqs/zizek.rb/blob/main/CHANGELOG.md",
    "documentation_uri" => "https://github.com/wallyqs/zizek.rb/blob/main/GUIDE.md",
    "bug_tracker_uri" => "https://github.com/wallyqs/zizek.rb/issues",
    "rubygems_mfa_required" => "true"
  }

  # Listed explicitly rather than from `git ls-files` so the manifest is the
  # same whether the gem is built in the monorepo, in the mirror, or from an
  # unpacked tarball. Sorted so two builds of one commit agree byte for byte.
  spec.files = Dir[
    "lib/**/*.rb",
    "examples/*.rb",
    "docs/assets/*.svg",
    "CHANGELOG.md",
    "GUIDE.md",
    "LICENSE",
    "README.md"
  ].sort
  spec.require_paths = ["lib"]
  spec.extra_rdoc_files = ["README.md", "GUIDE.md", "CHANGELOG.md", "LICENSE"]

  # The core is emitted for a 2.6-era Ruby and the package draws on nothing
  # newer; releases are exercised on the versions listed in CHANGELOG.md.
  spec.required_ruby_version = ">= 2.6"
  spec.required_rubygems_version = ">= 3.0"

  spec.add_development_dependency "minitest", "~> 5"
  # Only needed to exercise lib/zizek/rspec.rb; the integration file is
  # loaded on demand, so the gem has no runtime dependency on rspec.
  spec.add_development_dependency "rspec", "~> 3"
end
