# frozen_string_literal: true

# Port of Hegel's Die Hard water-jug state machine. The "failure" is a solution:
# generation finds operations leaving exactly four litres in the five-litre jug,
# then structural shrinking removes every unnecessary operation.

require "zizek"

module DieHardExample
  LEGACY_ZIZEK_DIE_HARD_FAILURE =
    "AAwAAAABAAAKAQAAAAEBAAAKAQAAAAUBAAAKAQAAAAIBAAAKAQAAAAUBAAAKAQAAAAEBAAAKAQAAAAU="
  SHRUNK_DIE_HARD_FAILURE =
    "AXicbYo5CgAwDMPkQpeu/f9fc0AIgXixLfQBiSciWX6L3J5npdM1FrQAhg=="
  HEGEL_ZLIB_DIE_HARD_FAILURE =
    "AXicbYoxCgBACMPSg1tc/f9fdRBFcCgNIQ4ILEed1OYPvtPuNgAVzACA"

  class DieHard
    def initialize
      @small = 0
      @big = 0
    end

    def fill_small(_test_case)
      @small = 3
    end

    def fill_big(_test_case)
      @big = 5
    end

    def empty_small(_test_case)
      @small = 0
    end

    def empty_big(_test_case)
      @big = 0
    end

    def pour_small_into_big(_test_case)
      previous_big = @big
      @big = [5, @big + @small].min
      @small -= @big - previous_big
    end

    def pour_big_into_small(_test_case)
      previous_small = @small
      @small = [3, @small + @big].min
      @big -= @small - previous_small
    end

    def physics_of_jugs(_test_case)
      raise "small jug escaped its capacity" unless @small.between?(0, 3)
      raise "big jug escaped its capacity" unless @big.between?(0, 5)
    end

    def die_hard_problem_not_solved(test_case)
      test_case.note("small / big = #{@small} / #{@big}")
      raise "the five-litre jug contains four litres" if @big == 4
    end

    def rules
      %i[
        fill_small fill_big empty_small empty_big
        pour_small_into_big pour_big_into_small
      ].map do |name|
        Zizek::Stateful::Rule.new(name.to_s, ->(machine, test_case) { machine.public_send(name, test_case) })
      end
    end

    def invariants
      [
        Zizek::Stateful::Rule.new(
          "physics_of_jugs",
          ->(machine, test_case) { machine.physics_of_jugs(test_case) }
        ),
        Zizek::Stateful::Rule.new(
          "die_hard_problem_not_solved",
          ->(machine, test_case) { machine.die_hard_problem_not_solved(test_case) }
        )
      ]
    end
  end

  module_function

  def property(test_case)
    Zizek::Stateful.run(DieHard.new, test_case)
  end

  def find_and_replay_solution
    found =
      begin
        Zizek.check(method(:property), examples: 2_000, seed: 0)
        raise "the four-litre solution should be discovered"
      rescue Zizek::Failure => failure
        raise unless failure.property_cause.message.include?("four litres")
        raise unless failure.blob == SHRUNK_DIE_HARD_FAILURE

        failure
      end

    begin
      Zizek.check(method(:property), reproduce: found.blob)
    rescue Zizek::Failure => replayed
      raise unless replayed.notes.last == "small / big = 3 / 4"
    else
      raise "the shrunk jug solution must replay"
    end
    [LEGACY_ZIZEK_DIE_HARD_FAILURE, HEGEL_ZLIB_DIE_HARD_FAILURE].each do |blob|
      begin
        Zizek.check(method(:property), reproduce: blob)
      rescue Zizek::Failure => compatible
        raise unless compatible.notes.last == "small / big = 3 / 4"
        next
      end
      raise "a compatible jug solution did not replay"
    end
    found
  end
end

puts DieHardExample.find_and_replay_solution if $PROGRAM_NAME == __FILE__
