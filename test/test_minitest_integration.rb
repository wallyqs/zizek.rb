# frozen_string_literal: true

# The Minitest integration, tested through Minitest.
#
# A property that fails has to be run without failing this suite, so the
# properties under test are defined on a throwaway class and driven directly.

require "minitest/autorun"
require "zizek/minitest"

class MinitestIntegrationTest < Minitest::Test
  G = Zizek::Generators

  def test_integration_helpers_are_private
    %i[included test_method_name run_property build].each do |name|
      refute_respond_to Zizek::Minitest, name
    end
    assert_raises(NoMethodError) { Zizek::Minitest.build(nil, {}, nil) }
    assert_raises(NameError) { Zizek::Minitest::ClassMethods }
  end

  # Run one property body the way the integration would, and return what
  # Minitest would have seen: :passed, a Minitest::Assertion, or the error.
  def outcome(test_class, name)
    test_class.new(name).tap { |test| test.send(name) }
    :passed
  rescue Minitest::Assertion => failure
    failure
  rescue StandardError => error
    error
  end

  def test_property_defines_a_real_test_method
    klass = Class.new(Minitest::Test) do
      include Zizek::Minitest
      property("the split is exact", n: G.integers(0..3)) { |n| assert_operator n, :<=, 3 }
    end
    assert_includes klass.instance_methods, :test_the_split_is_exact
    assert_equal :passed, outcome(klass, :test_the_split_is_exact)
  end

  def test_a_passing_property_registers_an_assertion
    klass = Class.new(Minitest::Test) do
      include Zizek::Minitest
      property("holds", n: G.integers(0..3), settings: { examples: 5 }) { |_n| nil }
    end
    test = klass.new(:test_holds)
    test.send(:test_holds)
    assert_operator test.assertions, :>, 0,
                    "a property that never asserts should still count as one"
  end

  def test_a_failed_assertion_is_reported_as_a_minitest_failure
    klass = Class.new(Minitest::Test) do
      include Zizek::Minitest
      property("is always zero", n: G.integers(0..9)) { |n| assert_equal 0, n }
    end
    failure = outcome(klass, :test_is_always_zero)
    assert_kind_of Minitest::Assertion, failure
    assert_includes failure.message, "Falsifying example: (n=1)"
    assert_includes failure.message, "reproduce with:"
  end

  def test_a_raised_exception_stays_an_error
    klass = Class.new(Minitest::Test) do
      include Zizek::Minitest
      property("never raises", n: G.integers(0..9)) { |n| raise "kaboom" if n > 3 }
    end
    error = outcome(klass, :test_never_raises)
    assert_kind_of Zizek::Failure, error
    assert_kind_of RuntimeError, error.property_cause
    assert_includes error.message, "Falsifying example: (n=4)"
  end

  def test_a_property_without_generators_is_handed_the_test_case
    klass = Class.new(Minitest::Test) do
      include Zizek::Minitest
      property("draws by hand", settings: { examples: 5, seed: 2 }) do |test_case|
        assert_operator test_case.integer(0, 5), :<=, 5
      end
    end
    assert_equal :passed, outcome(klass, :test_draws_by_hand)
  end

  def test_settings_reach_the_run
    seen = 0
    counter = -> { seen += 1 }
    klass = Class.new(Minitest::Test) do
      include Zizek::Minitest
      property("counts", settings: { examples: 12 }) { |_test_case| counter.call }
    end
    klass.new(:test_counts).send(:test_counts)
    assert_equal 12, seen
  end

  def test_a_duplicate_description_is_rejected_rather_than_overwriting
    assert_raises(ArgumentError) do
      Class.new(Minitest::Test) do
        include Zizek::Minitest
        property("same name") { |_test_case| nil }
        property("same name") { |_test_case| nil }
      end
    end
  end

  def test_a_property_needs_a_block
    assert_raises(ArgumentError) do
      Class.new(Minitest::Test) do
        include Zizek::Minitest
        property("no block", n: G.integers(0..1))
      end
    end
  end
end
