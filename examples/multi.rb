# frozen_string_literal: true

# Port of Hegel's two-assertion example. Zizek reports the first failure found
# and preserves that assertion site while shrinking, so a candidate which trips
# the other assertion cannot be mistaken for progress on the selected bug.

require "zizek"

module MultiExample
  EDGE = 1_337

  module_function

  def property(test_case)
    value = test_case.draw(
      Zizek::Generators.integers.min_value(0).max_value(2_000)
    )
    raise "#{value} hit the forbidden edge" if value == EDGE
    raise "#{value} is not below the edge" unless value < EDGE
  end

  def find_and_replay_one_origin
    found =
      begin
        Zizek.check(method(:property), examples: 100, seed: 1)
        raise "one of the two integer bugs should be discovered"
      rescue Zizek::Failure => failure
        message = failure.property_cause.message
        unless message.include?("forbidden edge") || message.include?("not below the edge")
          raise "unexpected failure origin: #{message}"
        end
        failure
      end

    begin
      Zizek.check(method(:property), reproduce: found.blob)
    rescue Zizek::Failure => replayed
      raise unless replayed.property_cause.message == found.property_cause.message

      return found
    end
    raise "the selected failure origin must replay"
  end
end

puts MultiExample.find_and_replay_one_origin if $PROGRAM_NAME == __FILE__
