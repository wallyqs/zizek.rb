# frozen_string_literal: true

# Port of Hypothesis's introductory bounded-integer example. The property is
# deliberately false from 50 onward, so shrinking should report the first
# failing boundary rather than merely the random value which exposed it.

require "zizek"

module HypothesisQuickstartExample
  SHRUNK_BOUNDARY_FAILURE = "AAEAAAAACgEAAAAy"

  module_function

  def property(test_case)
    value = test_case.draw(
      Zizek::Generators.integers.min_value(0).max_value(200)
    )
    raise "#{value} is not less than 50" unless value < 50
  end

  def find_and_replay_boundary
    found =
      begin
        Zizek.check(method(:property), examples: 100, seed: 1)
        raise "the boundary bug should be discovered"
      rescue Zizek::Failure => failure
        raise unless failure.property_cause.message == "50 is not less than 50"
        raise unless failure.blob == SHRUNK_BOUNDARY_FAILURE

        failure
      end

    begin
      Zizek.check(method(:property), reproduce: found.blob)
    rescue Zizek::Failure => replayed
      raise unless replayed.property_cause.message == found.property_cause.message

      return found
    end
    raise "the shrunk boundary failure must replay"
  end
end

puts HypothesisQuickstartExample.find_and_replay_boundary if $PROGRAM_NAME == __FILE__
