# frozen_string_literal: true

require "minitest"
require_relative "../zizek"

module Zizek
  # Property tests as ordinary Minitest tests.
  #
  #   require "zizek/minitest"
  #
  #   class SplitBillTest < Minitest::Test
  #     include Zizek::Minitest
  #
  #     property "the split is exact",
  #              total:  Zizek::Generators.integers(0..10_000),
  #              people: Zizek::Generators.integers(1..50) do |total, people|
  #       assert_equal total, split(total, people).sum
  #     end
  #   end
  #
  # Each `property` defines a real test method, so `rake test`, `-n`, seeds,
  # reporters, and `setup`/`teardown` all work unchanged. The block runs with
  # `self` bound to the test instance, so ordinary assertions are available and
  # a passing property registers one — a property that never asserts is
  # otherwise indistinguishable from a test that forgot to.
  #
  # Named draws are reported in the failure, so a counterexample says which
  # values failed without the property having to `note` them itself.
  module Minitest
    # Reserved: run settings for this property, not a generator.
    #
    #   property "converges", settings: { examples: 2_000, seed: 7 }
    SETTINGS_KEYWORD = :settings

    def self.included(base)
      base.extend(ClassMethods)
    end

    private_class_method :included

    module ClassMethods
      def property(description, settings: {}, **generators, &block)
        raise ArgumentError, "property #{description.inspect} needs a block" if block.nil?

        name = Zizek::Minitest.__send__(:test_method_name, description)
        if method_defined?(name) || private_method_defined?(name)
          raise ArgumentError,
                "#{self} already defines #{name}; give this property a distinct description"
        end

        define_method(name) do
          Zizek::Minitest.__send__(:run_property, self, generators, settings, block)
        end
        name
      end
    end

    private_constant :ClassMethods, :SETTINGS_KEYWORD

    class << self
      private

      def test_method_name(description)
        slug = description.to_s.strip.gsub(/[^0-9A-Za-z]+/, "_").gsub(/\A_+|_+\z/, "")
        raise ArgumentError, "property description must contain a word character" if slug.empty?

        :"test_#{slug}"
      end

      # Run one property inside a test instance.
      #
      # A failure whose cause is an assertion is reported as a Minitest
      # failure, because that is what it is; anything else stays an error, so
      # a raised exception does not get relabelled as a failed assertion.
      def run_property(test, generators, settings, block)
        Zizek.check(build(test, generators, block), **settings)
        test.assert(true, "the property held")
      rescue Zizek::Failure => failure
        raise failure unless failure.property_cause.is_a?(::Minitest::Assertion)

        test.flunk(failure.message)
      end

      def build(test, generators, block)
        return ->(test_case) { test.instance_exec(test_case, &block) } if generators.empty?

        lambda do |test_case|
          values = generators.map { |name, generator| test_case.draw(generator, name: name) }
          test.instance_exec(*values, &block)
        end
      end
    end
  end
end
