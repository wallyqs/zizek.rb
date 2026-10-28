# frozen_string_literal: true

# A tour of Zizek's draw and configuration surface, one scenario per feature:
#
#   1. bounded integers with a custom shrink target;
#   2. assumptions that reject examples instead of failing them;
#   3. boolean and byte draws shrinking together;
#   4. bounded IEEE-754 floats with portable shrinking; and
#   5. rejection limits (Zizek::TooManyRejections).
#
# Every scenario is deterministic: it uses a fixed seed and prints the shrunk
# failure it expects to find.

require "zizek"

module TourExample
  module_function

  # shrink_towards: failures shrink to the failing value closest to the
  # requested target instead of the interval minimum.
  def shrink_targets
    property = lambda do |test_case|
      value = test_case.draw(
        Zizek::Generators.integers.min_value(-1000).max_value(1000).shrink_towards(500)
      )
      test_case.note("value #{value}")
      raise "value #{value} exceeds the budget of 700" if value > 700
    end

    begin
      Zizek.check(property, examples: 300, seed: 1)
      raise "expected a failure above 700"
    rescue Zizek::Failure => failure
      failure
    end
  end

  # assume: odd draws are rejected (not failed), so the shrunk counterexample
  # is the smallest *even* value above the limit.
  def even_numbers_only
    property = lambda do |test_case|
      value = test_case.integer(0, 100)
      test_case.assume(value.even?)
      test_case.note("even value #{value}")
      raise "even value #{value} exceeds 50" if value > 50
    end

    begin
      Zizek.check(property, examples: 300, seed: 1)
      raise "expected an even failure above 50"
    rescue Zizek::Failure => failure
      failure
    end
  end

  # Low-level boolean and bytes draws shrinking together: the boolean stays
  # true because false passes, and the payload shrinks to the single smallest
  # high byte.
  def flags_and_bytes
    property = lambda do |test_case|
      compressed = test_case.boolean
      payload = test_case.bytes(1, 4)
      test_case.note("compressed=#{compressed} payload=#{payload.unpack1('H*')}")
      next unless compressed

      payload.each_byte do |value|
        raise format("compressed payload contains high byte 0x%02x", value) if value >= 0x80
      end
    end

    begin
      Zizek.check(property, examples: 300, seed: 1)
      raise "expected a high-byte failure"
    rescue Zizek::Failure => failure
      failure
    end
  end

  # Float generation, replay, and shrink ordering use the compiled float
  # choice. The smallest value outside [0, 1) is exactly 1.0.
  def bounded_floats
    property = lambda do |test_case|
      value = test_case.draw(
        Zizek::Generators.floats.min_value(0.0).max_value(10.0)
      )
      test_case.note("value #{value.inspect}")
      raise "float #{value.inspect} is outside [0, 1)" if value >= 1.0
    end

    begin
      Zizek.check(property, examples: 300, seed: 1)
      raise "expected a float failure"
    rescue Zizek::Failure => failure
      failure
    end
  end

  # max_rejections: a property whose assumptions reject every example stops
  # with TooManyRejections instead of searching forever.
  def rejection_limit
    property = lambda do |test_case|
      value = test_case.integer(0, 1000)
      test_case.assume(value > 1000) # impossible: every example is rejected
    end

    begin
      Zizek.check(property, examples: 10, max_rejections: 20, seed: 1)
      raise "expected TooManyRejections"
    rescue Zizek::TooManyRejections => rejected
      rejected
    end
  end
end

if $PROGRAM_NAME == __FILE__
  puts "== 1. integers with a shrink target =="
  puts TourExample.shrink_targets.message
  puts "\n== 2. assumptions =="
  puts TourExample.even_numbers_only.message
  puts "\n== 3. booleans and bytes =="
  puts TourExample.flags_and_bytes.message
  puts "\n== 4. bounded floats =="
  puts TourExample.bounded_floats.message
  puts "\n== 5. rejection limits =="
  puts TourExample.rejection_limit.message
end
