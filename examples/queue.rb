# frozen_string_literal: true

# Model-based stateful example: a bounded ring queue vs a plain array model.
#
# Demonstrates:
#   - manual state machines (Zizek::Stateful::Rule, Zizek::Stateful.run);
#   - assumptions inside rules (pop is rejected while the queue is empty);
#   - invariants checked after every successful rule;
#   - failure capture — the bug eventually reads past the backing array; and
#   - structural shrinking of whole rule spans plus blob replay.

require "zizek"

module QueueExample
  CAPACITY = 2

  # The shrunk failure blob is identical in Go, Python, and Ruby.
  PORTABLE_QUEUE_FAILURE =
    "AXicjcnBCQBACAPB3e8VcP2XqiL4E8xnQvIB5UmlcYrbkp7ONAAiJQCa"

  # A fixed-capacity FIFO queue over a circular buffer. Pop wraps the head
  # index one slot too late — a deliberate off-by-one that reads past the
  # backing array (returning nil) on the third pop.
  class RingQueue
    attr_reader :size

    def initialize
      @data = Array.new(CAPACITY, 0)
      @head = 0
      @tail = 0
      @size = 0
    end

    def push(value)
      return false if size == CAPACITY

      @data[@tail] = value
      @tail = (@tail + 1) % CAPACITY
      @size += 1
      true
    end

    def pop
      value = @data[@head]
      @head = (@head + 1) % (CAPACITY + 1) # BUG: should wrap modulo CAPACITY
      @size -= 1
      value
    end
  end

  class QueueTest
    def initialize
      @queue = RingQueue.new
      @model = []
    end

    def push(test_case)
      value = test_case.draw(Zizek::Generators.integers.min_value(0).max_value(99))
      if @queue.push(value)
        @model << value
        test_case.note("push #{value}")
      else
        test_case.note("push #{value} refused: queue full")
      end
    end

    def pop(test_case)
      test_case.assume(!@model.empty?)
      want = @model.shift
      got = @queue.pop
      test_case.note("pop -> #{got.inspect}")
      raise "pop returned #{got.inspect}, expected #{want}" unless got == want
    end

    def sizes_agree(_test_case)
      return if @queue.size == @model.length

      raise "queue reports #{@queue.size} items, model holds #{@model.length}"
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
          "sizes_agree",
          ->(machine, test_case) { machine.sizes_agree(test_case) }
        )
      ]
    end
  end

  module_function

  def property(test_case)
    Zizek::Stateful.run(QueueTest.new, test_case)
  end

  def find_and_replay_bug
    found =
      begin
        Zizek.check(method(:property), examples: 2_000, seed: 3)
        raise "the ring-queue off-by-one should be discovered"
      rescue Zizek::Failure => failure
        failure
      end

    begin
      Zizek.check(method(:property), reproduce: found.blob)
    rescue Zizek::Failure
      return found
    end
    raise "the shrunk queue failure must replay"
  end
end

puts QueueExample.find_and_replay_bug if $PROGRAM_NAME == __FILE__
