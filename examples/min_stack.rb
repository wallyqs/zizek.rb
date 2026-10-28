# frozen_string_literal: true

# Port of Hegel's minimum-stack state machine. MinStack deliberately forgets
# duplicate minima: after push(0), push(0), pop, its cached minimum is empty
# while the reference stack still contains zero.

require "zizek"

module MinStackExample
  SHRUNK_MIN_STACK_FAILURE =
    "AXicdYixCQAACIB0jf6/tyJoy0UxASVkWHnhd9oFC6sAWQ=="

  class MinStack
    attr_reader :stack

    def initialize
      @stack = []
      @minimums = []
    end

    def push(value)
      stack << value
      @minimums << value if minimum.nil? || value < minimum
    end

    def pop
      value = stack.pop
      @minimums.pop if !value.nil? && minimum == value
      value
    end

    def minimum
      @minimums.last
    end

    def reference_minimum
      stack.min
    end
  end

  class MinStackTest
    def initialize
      @stack = MinStack.new
    end

    def push(test_case)
      value = test_case.draw(Zizek::Generators.integers)
      test_case.note("push #{value}")
      @stack.push(value)
    end

    def pop(test_case)
      test_case.note("pop #{@stack.pop.inspect}")
    end

    def minimums_agree(_test_case)
      return if @stack.minimum == @stack.reference_minimum

      raise "cached minimum #{@stack.minimum.inspect}, expected #{@stack.reference_minimum.inspect}"
    end

    def rules
      [
        Zizek::Stateful::Rule.new("push", ->(machine, test_case) { machine.push(test_case) }),
        Zizek::Stateful::Rule.new("pop", ->(machine, test_case) { machine.pop(test_case) })
      ]
    end

    def invariants
      [
        Zizek::Stateful::Rule.new(
          "minimums_agree",
          ->(machine, test_case) { machine.minimums_agree(test_case) }
        )
      ]
    end
  end

  module_function

  def property(test_case)
    Zizek::Stateful.run(MinStackTest.new, test_case)
  end

  def find_and_replay_bug
    found =
      begin
        Zizek.check(method(:property), examples: 2_000, seed: 1)
        raise "the duplicate-minimum bug should be discovered"
      rescue Zizek::Failure => failure
        raise unless failure.property_cause.message.include?("cached minimum")
        raise unless failure.blob == SHRUNK_MIN_STACK_FAILURE

        failure
      end

    begin
      Zizek.check(method(:property), reproduce: found.blob)
    rescue Zizek::Failure => replayed
      raise unless replayed.property_cause.message == found.property_cause.message

      return found
    end
    raise "the shrunk min-stack failure must replay"
  end
end

puts MinStackExample.find_and_replay_bug if $PROGRAM_NAME == __FILE__
