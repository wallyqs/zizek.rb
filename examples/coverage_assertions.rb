# frozen_string_literal: true

# Coverage assertions: catching the test that passes for the wrong reason.
#
# Demonstrates:
#   - `always`, an ordinary failure that shrinks to the boundary it crossed;
#   - `unreachable`, shrinking to the simplest input reaching a branch;
#   - `sometimes`, failing a run whose interesting branch never executed;
#   - `cover(percent:)`, requiring a rate rather than a single sighting; and
#   - `must_cover:`, declaring a label whose call site itself may never run.
#
# The code under test is a clamp that forgot its ceiling. Every scenario is
# deterministic: it uses a fixed seed and prints the verdict it expects.

require "zizek"

module CoverageAssertionsExample
  module_function

  # Clamp `value` into [floor, ceiling]. Deliberate bug: the ceiling check
  # compares against the floor, so values above the ceiling pass through.
  def clamp(value, floor, ceiling)
    return floor if value < floor
    return ceiling if value < floor # BUG: should be `if value > ceiling`

    value
  end

  # `always` is a per-example assertion. It fails like any other failure, so
  # it shrinks: the reported example is the *smallest* value that escapes the
  # ceiling, 101, not whatever large value was found first.
  def always_shrinks_to_the_boundary
    property = lambda do |test_case|
      value = test_case.integer(0, 1000)
      clamped = clamp(value, 0, 100)
      test_case.always("clamped into range", clamped.between?(0, 100))
    end

    begin
      Zizek.check(property, examples: 300, seed: 1)
      raise "the broken ceiling should be discovered"
    rescue Zizek::Failure => failure
      failure
    end
  end

  # `unreachable` asserts a branch is dead. When it is not, the failure
  # shrinks to the simplest input that reaches it.
  def unreachable_finds_the_simplest_path
    property = lambda do |test_case|
      value = test_case.integer(0, 1000)
      test_case.unreachable("value escaped the clamp") if clamp(value, 0, 100) > 100
    end

    begin
      Zizek.check(property, examples: 300, seed: 1)
      raise "the escape branch should be reached"
    rescue Zizek::Failure => failure
      failure
    end
  end

  # `sometimes` judges the completed run, not the current example. Here the
  # property itself holds on every draw — the generator never exceeds the
  # ceiling, so the clamp is never exercised where it is broken. Without the
  # coverage assertion this run would go green and prove nothing.
  def sometimes_fails_the_vacuous_pass
    property = lambda do |test_case|
      value = test_case.integer(0, 100) # never above the ceiling: too narrow
      clamped = clamp(value, 0, 100)
      test_case.sometimes("saturated at the ceiling", clamped == 100 && value > 100)
      raise "clamp raised the value" if clamped > value
    end

    begin
      Zizek.check(property, examples: 200, seed: 1)
      raise "the run should fail its coverage requirement"
    rescue Zizek::FailedCoverage => missed
      missed
    end
  end

  # `cover` is `sometimes` with a required rate over the run's valid examples.
  # Values 0..1000 clamped into [0, 100] leave ~90% of draws above the
  # ceiling, so demanding that 60% of examples stay *below* it must fail —
  # and the verdict reports the observed counters.
  def cover_reports_the_observed_rate
    property = lambda do |test_case|
      value = test_case.integer(0, 1000)
      test_case.cover("left below the ceiling", value <= 100, percent: 60)
    end

    begin
      Zizek.check(property, examples: 200, seed: 1)
      raise "the run should miss the 60% requirement"
    rescue Zizek::FailedCoverage => missed
      missed
    end
  end

  # A call site registers its label the first time it *runs*. This
  # `sometimes` sits inside a branch the generator can never enter, so the
  # run never even learns the label exists — declaring it in `must_cover:`
  # is what turns that silence into a verdict.
  def must_cover_catches_the_unregistered_label
    property = lambda do |test_case|
      value = test_case.integer(0, 50)
      if value > 100 # unreachable with these bounds
        test_case.sometimes("overflow path", true)
      end
    end

    begin
      Zizek.check(
        property,
        examples: 100,
        seed: 1,
        must_cover: [Zizek::Coverage.new("overflow path")]
      )
      raise "the run should fail the declared requirement"
    rescue Zizek::FailedCoverage => missed
      missed
    end
  end
end

if $PROGRAM_NAME == __FILE__
  puts "== 1. always: fails and shrinks to the boundary =="
  puts CoverageAssertionsExample.always_shrinks_to_the_boundary.message
  puts "\n== 2. unreachable: shrinks to the simplest reaching input =="
  puts CoverageAssertionsExample.unreachable_finds_the_simplest_path.message
  puts "\n== 3. sometimes: the vacuous pass becomes a failure =="
  puts CoverageAssertionsExample.sometimes_fails_the_vacuous_pass.message
  puts "\n== 4. cover: a required rate, with observed counters =="
  puts CoverageAssertionsExample.cover_reports_the_observed_rate.message
  puts "\n== 5. must_cover: a label whose call site never ran =="
  puts CoverageAssertionsExample.must_cover_catches_the_unregistered_label.message
end
