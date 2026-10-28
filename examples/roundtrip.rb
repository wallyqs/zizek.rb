# frozen_string_literal: true

# Round-trip property example: run-length encoding.
#
# Demonstrates:
#   - the portable text generator (Zizek::Generators.text);
#   - notes attached to the failing example (test_case.note);
#   - shrinking to a minimal counterexample; and
#   - replaying the portable reproduce blob.

require "zizek"

module RoundtripExample
  # The shrunk failure blob is identical in Go, Python, and Ruby.
  PORTABLE_ROUNDTRIP_FAILURE = "AAEAAAAEAQAAADAAAAA="

  module_function

  # Compresses text into [count, char] runs. Deliberate bug: the run in
  # progress is never flushed when the input ends, so the final run of every
  # non-empty input is lost.
  def encode(text)
    runs = []
    count = 0
    current = nil
    text.each_char do |char|
      if count.positive? && char == current
        count += 1
        next
      end
      runs << [count, current] if count.positive?
      current = char
      count = 1
    end
    runs
  end

  def decode(runs)
    runs.map { |count, char| char * count }.join
  end

  def property(test_case)
    text = test_case.draw(Zizek::Generators.text.max_size(12))
    test_case.note("text #{text.inspect} encodes to #{encode(text).inspect}")
    decoded = decode(encode(text))
    return if decoded == text

    raise "round trip lost data: #{text.inspect} became #{decoded.inspect}"
  end

  def find_and_replay_bug
    found =
      begin
        Zizek.check(method(:property), examples: 200, seed: 1)
        raise "the round-trip bug should be discovered"
      rescue Zizek::Failure => failure
        failure
      end

    # The blob is a portable description of the shrunk choices: replaying it
    # runs exactly the recorded example, here or in any other Zizek package.
    begin
      Zizek.check(method(:property), reproduce: found.blob)
    rescue Zizek::Failure
      return found
    end
    raise "the shrunk round-trip failure must replay"
  end
end

puts RoundtripExample.find_and_replay_bug if $PROGRAM_NAME == __FILE__
