# frozen_string_literal: true

# Port of Hegel's passing stack state machine. It demonstrates a model whose
# rules include an assumption: push_pop is rejected while the stack is empty,
# without rejecting the whole generated example.

require "zizek"

module StackExample
  class IntegerStack
    def initialize
      @stack = []
    end

    def push(test_case)
      @stack << test_case.draw(Zizek::Generators.integers)
    end

    def pop(_test_case)
      @stack.pop
    end

    def pop_push(test_case)
      value = test_case.draw(Zizek::Generators.integers)
      initial = @stack.dup
      @stack << value
      raise "pop did not return the pushed value" unless @stack.pop == value
      raise "push then pop changed the stack" unless @stack == initial
    end

    def push_pop(test_case)
      initial = @stack.dup
      value = @stack.pop
      test_case.assume(!value.nil?)
      @stack << value
      raise "pop then push changed the stack" unless @stack == initial
    end

    def rules
      [
        Zizek::Stateful::Rule.new("push", ->(machine, test_case) { machine.push(test_case) }),
        Zizek::Stateful::Rule.new("pop", ->(machine, test_case) { machine.pop(test_case) }),
        Zizek::Stateful::Rule.new("pop_push", ->(machine, test_case) { machine.pop_push(test_case) }),
        Zizek::Stateful::Rule.new("push_pop", ->(machine, test_case) { machine.push_pop(test_case) })
      ]
    end

    def invariants
      []
    end
  end

  module_function

  def property(test_case)
    Zizek::Stateful.run(IntegerStack.new, test_case)
  end

  def verify_stack_model
    Zizek.check(method(:property), examples: 100, seed: 1)
    true
  end
end

if $PROGRAM_NAME == __FILE__
  StackExample.verify_stack_model
  puts "stack model passed"
end
