# frozen_string_literal: true

# The RSpec integration, tested through Minitest.
#
# RSpec is an optional development dependency: the integration file is only
# loaded when a user requires it, and this suite skips when it is absent
# rather than failing a checkout that does not have the gem.

require "minitest/autorun"
# The package itself is not optional, only the integration is, and the two have
# to be required separately: zizek/rspec requires "rspec/core" *before* it
# requires the package, so on a checkout without the gem the LoadError below
# fires with Zizek still undefined. Folding this require into the begin/rescue
# would leave the class body referencing a constant that does not exist, which
# fails the run this suite is written to skip.
require "zizek"

begin
  require "zizek/rspec"
  RSPEC_AVAILABLE = true
rescue LoadError
  RSPEC_AVAILABLE = false
end

class RSpecIntegrationTest < Minitest::Test
  G = Zizek::Generators unless defined?(G)

  def setup
    skip "rspec is not installed" unless RSPEC_AVAILABLE
  end

  def test_integration_helpers_are_private
    %i[run_property build expectation_failure?].each do |name|
      refute_respond_to Zizek::RSpec, name
    end
    assert_raises(NoMethodError) { Zizek::RSpec.build(nil, {}, nil) }
    assert_includes Zizek::RSpec::DSL.public_instance_methods(false), :property
  end

  # Build a one-example group, run it in isolation with no output, and report
  # what RSpec saw.
  def run_group(&definition)
    group = RSpec.describe("zizek", &definition)
    group.run(RSpec::Core::NullReporter)
    group.examples.map(&:execution_result)
  end

  def test_property_defines_an_example_that_passes
    results = run_group do
      property("holds", n: G.integers(0..3)) { |n| expect(n).to be <= 3 }
    end
    assert_equal [:passed], results.map(&:status)
  end

  def test_a_failed_expectation_carries_the_falsifying_example_and_blob
    results = run_group do
      property("is always zero", n: G.integers(0..9)) { |n| expect(n).to eq(0) }
    end
    assert_equal [:failed], results.map(&:status)
    message = results.first.exception.message
    assert_includes message, "Falsifying example: (n=1)"
    assert_includes message, "reproduce with:"
  end

  def test_a_raised_exception_still_fails_the_example
    results = run_group do
      property("never raises", n: G.integers(0..9)) { |n| raise "kaboom" if n > 3 }
    end
    assert_equal [:failed], results.map(&:status)
    assert_kind_of Zizek::Failure, results.first.exception
  end

  def test_a_property_without_generators_is_handed_the_test_case
    results = run_group do
      property("draws by hand", settings: { examples: 5, seed: 2 }) do |test_case|
        expect(test_case.integer(0, 5)).to be <= 5
      end
    end
    assert_equal [:passed], results.map(&:status)
  end

  def test_the_example_context_is_available_inside_the_property
    results = run_group do
      let(:ceiling) { 9 }
      property("uses let", n: G.integers(0..9)) { |n| expect(n).to be <= ceiling }
    end
    assert_equal [:passed], results.map(&:status)
  end

  def test_a_property_needs_a_block
    assert_raises(ArgumentError) do
      run_group { property("no block", n: G.integers(0..1)) }
    end
  end
end
