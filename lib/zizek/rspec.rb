# frozen_string_literal: true

require "rspec/core"
require_relative "../zizek"

module Zizek
  # Property tests as ordinary RSpec examples.
  #
  #   require "zizek/rspec"
  #
  #   RSpec.describe Splitter do
  #     property "the split is exact",
  #              total:  Zizek::Generators.integers(0..10_000),
  #              people: Zizek::Generators.integers(1..50) do |total, people|
  #       expect(described_class.split(total, people).sum).to eq(total)
  #     end
  #   end
  #
  # `property` defines a real example, so filters, tags, formatters, `let`, and
  # `before` hooks all work unchanged. The block runs in the example's own
  # context, so matchers and helpers are available.
  #
  # Requiring this file registers the DSL on every example group. To scope it
  # instead, skip the require and `config.extend Zizek::RSpec::DSL, type: :prop`.
  module RSpec
    module DSL
      def property(description, settings: {}, **generators, &block)
        raise ArgumentError, "property #{description.inspect} needs a block" if block.nil?

        it(description) do
          Zizek::RSpec.__send__(:run_property, self, generators, settings, block)
        end
      end
    end

    class << self
      private

      def run_property(example, generators, settings, block)
        Zizek.check(build(example, generators, block), **settings)
      rescue Zizek::Failure => failure
        raise failure unless expectation_failure?(failure.property_cause)

        # Re-raise as the matcher error so RSpec renders it as a failed
        # expectation rather than an unexpected exception, keeping the
        # falsifying example and the blob in the message.
        raise ::RSpec::Expectations::ExpectationNotMetError, failure.message
      end

      def build(example, generators, block)
        return ->(test_case) { example.instance_exec(test_case, &block) } if generators.empty?

        lambda do |test_case|
          values = generators.map { |name, generator| test_case.draw(generator, name: name) }
          example.instance_exec(*values, &block)
        end
      end

      def expectation_failure?(error)
        defined?(::RSpec::Expectations::ExpectationNotMetError) &&
          error.is_a?(::RSpec::Expectations::ExpectationNotMetError)
      end
    end
  end
end

::RSpec.configure { |config| config.extend Zizek::RSpec::DSL }
