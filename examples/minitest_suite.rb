# frozen_string_literal: true

# Properties as ordinary Minitest tests.
#
# Demonstrates:
#   - `property` defining real test methods, collected by any runner;
#   - named draws, so the failure names the values instead of the property
#     having to `note` them;
#   - a failed assertion reported as a Minitest failure, carrying the
#     reproduce blob; and
#   - per-property settings.
#
# Run it directly:
#
#   ruby -Ilib examples/minitest_suite.rb
#
# One test is expected to fail: that is the point of the example. It prints
# the falsifying example and a blob you can paste into `reproduce:`.

require "minitest/autorun"
require "zizek/minitest"

G = Zizek::Generators

module Bill
  module_function

  # Split `total` cents between `people`, giving the remainder to nobody.
  # The remainder is the bug: the parts do not add back up to the total.
  def split(total, people)
    Array.new(people, total / people)
  end
end

class BillTest < Minitest::Test
  include Zizek::Minitest

  # Passing: every share is non-negative and no larger than the total.
  property "shares stay within the bill",
           total: G.integers(0..10_000),
           people: G.integers(1..50) do |total, people|
    shares = Bill.split(total, people)
    assert_equal people, shares.length
    shares.each do |share|
      assert_operator share, :>=, 0
      assert_operator share, :<=, total
    end
  end

  # Failing: shrinks to the smallest bill that cannot be divided evenly.
  property "the split is exact",
           total: G.integers(0..10_000),
           people: G.integers(1..50) do |total, people|
    assert_equal total, Bill.split(total, people).sum
  end

  # A property that wants the test case itself gets it when no generators are
  # named, and settings ride along under the reserved `settings:` keyword.
  property "shares are stable across calls", settings: { examples: 250, seed: 11 } do |test_case|
    total = test_case.draw(G.integers(0..1_000), name: :total)
    people = test_case.draw(G.integers(1..20), name: :people)
    assert_equal Bill.split(total, people), Bill.split(total, people)
  end
end
