# frozen_string_literal: true

# Code generated from conformance/{draw_ops,shell_cases}.zir by emitter/emit.go; DO NOT EDIT.

module ZizekShellCases
  def self.run(test, kind, fields)
    case kind
    when "PROBE_EXTEND"
      test.assert_equal 6, fields.length, "PROBE_EXTEND field count"
      blob = fields[0]
      lo = fields[1].to_i
      hi = fields[2].to_i
      expected = fields[3]
      total = fields[4].to_i
      probe_seed = fields[5].to_i
      recorded = expected == "-" ? [] : expected.split(",").map(&:to_i)
      stream = Zizek.const_get(:Core).raw_failure_decode(blob)
      test.refute_nil stream, "unreadable reproduce blob"
      bare = Zizek::TestCase.new(replay: stream)
      test.assert_raises(Zizek::ReplayOverrun) { total.times { bare.integer(lo, hi) } }
      probe = Zizek::TestCase.new(rng: Random.new(probe_seed), replay: stream)
      drawn = Array.new(total) { probe.integer(lo, hi) }
      test.assert_equal recorded, drawn.first(recorded.length)
      test.assert_equal total, probe.__send__(:draws).length
      return [nil, true]
    when "SHRINK_DESCENDANT"
      test.assert_equal 4, fields.length, "SHRINK_DESCENDANT field count"
      hi = fields[0].to_i
      threshold = fields[1].to_i
      seed = fields[2].to_i
      examples = fields[3].to_i
      chain = lambda do |test_case|
        test_case.start_span("node")
        begin
          values = [test_case.integer(0, hi)]
          values.concat(chain.call(test_case)) if test_case.boolean
        ensure
          test_case.stop_span
        end
        values
      end
      property = lambda do |test_case|
        raise "the deepest node is too large" if chain.call(test_case).last >= threshold
      end
      failure = test.assert_raises(Zizek::Failure, "no failing chain was found") do
        Zizek.check(property, examples: examples, max_rejections: 2000, seed: seed)
      end
      seen = []
      replay = lambda do |test_case|
        seen << chain.call(test_case)
        raise "replay"
      end
      test.assert_raises(Zizek::Failure) { Zizek.check(replay, reproduce: failure.blob) }
      test.assert_equal [[threshold]], seen
      return [failure.blob, true]
    when "SHRINK_TRIVIAL"
      test.assert_equal 3, fields.length, "SHRINK_TRIVIAL field count"
      hi = fields[0].to_i
      seed = fields[1].to_i
      examples = fields[2].to_i
      draw = lambda do |test_case|
        guard = test_case.integer(0, hi)
        test_case.start_span("pair")
        begin
          first = test_case.integer(0, hi)
          flag = test_case.boolean
          second = test_case.integer(0, hi)
        ensure
          test_case.stop_span
        end
        [guard, first, flag, second]
      end
      property = lambda do |test_case|
        guard, first, _flag, second = draw.call(test_case)
        raise "guarded pair" if guard >= 1 && (first.zero? == second.zero?)
      end
      failure = test.assert_raises(Zizek::Failure) { Zizek.check(property, examples: examples, max_rejections: 1000, seed: seed) }
      seen = []
      replay = lambda do |test_case|
        seen << draw.call(test_case)
        raise "replay"
      end
      test.assert_raises(Zizek::Failure) { Zizek.check(replay, reproduce: failure.blob) }
      test.assert_equal [[1, 0, false, 0]], seen
      return [failure.blob, true]
    when "KEY_SEQUENCE"
      test.assert_equal 5, fields.length, "KEY_SEQUENCE field count"
      lo = fields[0].to_i
      hi = fields[1].to_i
      seed = fields[2].to_i
      examples = fields[3].to_i
      expected_misses = fields[4].to_i
      sim = lambda do |insert, countdown|
        lambda do |test_case|
          reads = []
          coins = []
          6.times do |step|
            if step.even?
              reads << test_case.integer(lo, hi, key: test_case.next_key("read"))
              reads << test_case.integer(lo, hi, key: test_case.next_key("read")) if insert && step.zero?
            else
              coins << test_case.integer(0, 1, key: test_case.next_key("coin"))
            end
          end
          test_case.note("#{reads}|#{coins}")
          countdown[0] += 1
          raise "boom" if countdown[0] >= 4
        end
      end
      begin
        Zizek.check(sim.call(false, [0]), examples: examples, max_rejections: 1000, max_shrinks: 1, seed: seed)
      rescue Zizek::Failure => failure
        reads, coins = failure.notes[0].split("|")
        replayed = test.assert_raises(Zizek::Failure) { Zizek.check(sim.call(true, [99]), reproduce: failure.blob) }
        got_reads, got_coins = replayed.notes[0].split("|")
        test.assert_equal "#{reads[0..-2]}, #{lo}]", got_reads
        test.assert_equal coins, got_coins
        test.assert_equal 0, replayed.puns
        test.assert_equal expected_misses, replayed.key_misses
      end
      return [nil, true]
    when "KEYED_REPLAY"
      test.assert_equal 7, fields.length, "KEYED_REPLAY field count"
      lo = fields[0].to_i
      hi = fields[1].to_i
      threshold = fields[2].to_i
      seed = fields[3].to_i
      examples = fields[4].to_i
      expected = fields[5].to_i
      expected_misses = fields[6].to_i
      first_key = Zizek.key_hash("read", 1)
      second_key = Zizek.key_hash("read", 2)
      fresh_key = Zizek.key_hash("retry", 1)
      recorded = lambda do |test_case|
        first = test_case.integer(lo, hi, key: first_key)
        second = test_case.integer(lo, hi, key: second_key)
        raise "both large" if first >= threshold && second >= threshold
      end
      failure = test.assert_raises(Zizek::Failure) { Zizek.check(recorded, examples: examples, max_rejections: 1000, seed: seed) }
      seen = []
      evolved = lambda do |test_case|
        second = test_case.integer(lo, hi, key: second_key)
        test_case.integer(lo, hi, key: fresh_key)
        first = test_case.integer(lo, hi, key: first_key)
        seen << [first, second]
        raise "replay"
      end
      replayed = test.assert_raises(Zizek::Failure) { Zizek.check(evolved, reproduce: failure.blob) }
      test.assert_equal [[expected, expected]], seen, "keyed draws resolve by name"
      test.assert_equal expected_misses, replayed.key_misses
      return [failure.blob, true]
    when "KEYED_DEEP_CLONE"
      test.assert_equal 4, fields.length, "KEYED_DEEP_CLONE field count"
      depth = fields[0].to_i
      hi = fields[1].to_i
      seed = fields[2].to_i
      examples = fields[3].to_i
      deep_key = Zizek.key_hash("deep")
      innermost = lambda do |test_case, levels|
        levels.times { test_case = test_case.clone_stream }
        test_case.integer(0, hi, key: deep_key)
      end
      property = lambda do |test_case|
        raise "the deepest keyed draw is too large" if innermost.call(test_case, depth) >= hi
      end
      failure = test.assert_raises(Zizek::Failure, "the deep keyed property did not fail") do
        Zizek.check(property, examples: examples, max_rejections: 1000, seed: seed)
      end
      test.refute_nil Zizek.const_get(:Core).raw_failure_decode(failure.blob), "unreadable reproduce blob"
      seen = []
      replay = lambda do |test_case|
        seen << innermost.call(test_case, depth)
        raise "replay"
      end
      test.assert_raises(Zizek::Failure) { Zizek.check(replay, reproduce: failure.blob) }
      test.assert_equal [hi], seen
      return [failure.blob, true]
    when "KEY_DIGEST"
      test.assert_equal 2, fields.length, "KEY_DIGEST field count"
      name = fields[0]
      expected = fields[1]
      test.assert_equal expected, format("%016x", Zizek.key_hash(name))
      return [nil, true]
    when "COST_FIRST"
      test.assert_equal 6, fields.length, "COST_FIRST field count"
      sites = fields[0].to_i
      bound = fields[1].to_i
      threshold = fields[2].to_i
      seed = fields[3].to_i
      examples = fields[4].to_i
      expected_faults = fields[5].to_i
      property = lambda do |test_case|
        fired = 0
        total = 0
        sites.times do |site|
          if test_case.boolean(key: test_case.next_key("inject", site))
            fired += 1
            test_case.cost("fault")
            next
          end
          total += test_case.integer(0, bound, key: test_case.next_key("payload", site))
        end
        test_case.note(fired.to_s)
        raise "boom" if fired.positive? && total >= threshold
      end
      failure = test.assert_raises(Zizek::Failure) { Zizek.check(property, examples: examples, max_rejections: 1000, seed: seed) }
      test.assert_equal expected_faults.to_s, failure.notes[0]
      test.assert_equal({ "fault" => expected_faults }, failure.costs)
      return [nil, true]
    when "TWO_BUG"
      test.assert_equal 6, fields.length, "TWO_BUG field count"
      lo = fields[0].to_i
      hi = fields[1].to_i
      a_threshold = fields[2].to_i
      b_value = fields[3].to_i
      seed = fields[4].to_i
      examples = fields[5].to_i
      declared_bug_a = Class.new(StandardError)
      declared_bug_b = Class.new(StandardError)
      found = nil
      property = lambda do |test_case|
        draw0 = test_case.integer(lo, hi)
        if draw0 > a_threshold
          found ||= "A"
          raise declared_bug_a, "bug A"
        end
        if draw0 == b_value
          found ||= "B"
          raise declared_bug_b, "bug B"
        end
      end
      begin
        Zizek.check(property, examples: examples, max_rejections: 1000, seed: seed)
      rescue Zizek::Failure => failure
        reported = failure.property_cause.is_a?(declared_bug_a) ? "A" : "B"
        test.assert_equal found, reported, "found bug #{found} but reported #{reported}"
      end
      return [nil, true]
    when "SHRINK_MIN"
      test.assert_equal 6, fields.length, "SHRINK_MIN field count"
      lo = fields[0].to_i
      hi = fields[1].to_i
      threshold = fields[2].to_i
      seed = fields[3].to_i
      examples = fields[4].to_i
      expected = fields[5].to_i
      property = lambda do |test_case|
        draw0 = test_case.integer(lo, hi)
        raise "declared failure" if draw0 >= threshold
      end
      begin
        Zizek.check(property, examples: examples, max_rejections: 1000, seed: seed)
      rescue Zizek::Failure => failure
        seen0 = []
        replay = lambda do |test_case|
          seen0 << test_case.integer(lo, hi)
          raise "replay"
        end
        test.assert_raises(Zizek::Failure) { Zizek.check(replay, reproduce: failure.blob) }
        test.assert_equal [expected], seen0, "draw 0 shrank to #{seen0.inspect} instead of [expected]"
        return [failure.blob, true]
      end
      [nil, true]
    when "SHRINK_SPARSE"
      test.assert_equal 5, fields.length, "SHRINK_SPARSE field count"
      hi = fields[0].to_i
      period = fields[1].to_i
      dense = fields[2].to_i
      seed = fields[3].to_i
      examples = fields[4].to_i
      property = lambda do |test_case|
        draw0 = test_case.integer(0, hi)
        raise "declared failure" if draw0 >= period && (draw0 % period == 0 || draw0 >= dense)
      end
      begin
        Zizek.check(property, examples: examples, max_rejections: 1000, seed: seed)
      rescue Zizek::Failure => failure
        seen0 = []
        replay = lambda do |test_case|
          seen0 << test_case.integer(0, hi)
          raise "replay"
        end
        test.assert_raises(Zizek::Failure) { Zizek.check(replay, reproduce: failure.blob) }
        test.assert_equal [period], seen0, "draw 0 shrank to #{seen0.inspect} instead of [period]"
        return [failure.blob, true]
      end
      [nil, true]
    when "SHRINK_DECLARED_LEN"
      test.assert_equal 4, fields.length, "SHRINK_DECLARED_LEN field count"
      hi = fields[0].to_i
      threshold = fields[1].to_i
      seed = fields[2].to_i
      examples = fields[3].to_i
      property = lambda do |test_case|
        draw0 = test_case.__send__(:collect, Zizek::Generators.integers(min: 0, max: hi), 0, 10, "list.element")
        draw1 = test_case.integer(0, 10)
        raise "declared failure" if draw1 == draw0.length && draw0.any? { |value| value >= threshold }
      end
      begin
        Zizek.check(property, examples: examples, max_rejections: 1000, seed: seed)
      rescue Zizek::Failure => failure
        seen0 = []
        seen1 = []
        replay = lambda do |test_case|
          seen0 << test_case.__send__(:collect, Zizek::Generators.integers(min: 0, max: hi), 0, 10, "list.element")
          seen1 << test_case.integer(0, 10)
          raise "replay"
        end
        test.assert_raises(Zizek::Failure) { Zizek.check(replay, reproduce: failure.blob) }
        test.assert_equal [[threshold]], seen0, "draw 0 shrank to #{seen0.inspect} instead of [[threshold]]"
        test.assert_equal [1], seen1, "draw 1 shrank to #{seen1.inspect} instead of [1]"
        return [failure.blob, true]
      end
      [nil, true]
    when "SHRINK_GATE"
      test.assert_equal 4, fields.length, "SHRINK_GATE field count"
      hi = fields[0].to_i
      threshold = fields[1].to_i
      seed = fields[2].to_i
      examples = fields[3].to_i
      draw = lambda do |test_case|
        coin = test_case.integer(0, hi)
        drawn = [coin]
        drawn << test_case.integer(0, 2) if coin < threshold
        drawn << test_case.integer(-1000, 1000)
        drawn
      end
      property = lambda do |test_case|
        draw.call(test_case)
        raise "the gate always fails"
      end
      failure = test.assert_raises(Zizek::Failure) { Zizek.check(property, examples: examples, max_rejections: 1000, seed: seed) }
      seen = []
      replay = lambda do |test_case|
        seen << draw.call(test_case)
        raise "replay"
      end
      test.assert_raises(Zizek::Failure) { Zizek.check(replay, reproduce: failure.blob) }
      test.assert_equal [[threshold, 0]], seen
      return [failure.blob, true]
    when "SHRINK_LIST"
      test.assert_equal 6, fields.length, "SHRINK_LIST field count"
      lo = fields[0].to_i
      hi = fields[1].to_i
      threshold = fields[2].to_i
      seed = fields[3].to_i
      examples = fields[4].to_i
      expected = fields[5].to_i
      property = lambda do |test_case|
        draw0 = test_case.__send__(:collect, Zizek::Generators.integers(min: lo, max: hi), 0, nil, "list.element")
        raise "declared failure" if draw0.any? { |value| value >= threshold }
      end
      begin
        Zizek.check(property, examples: examples, max_rejections: 1000, seed: seed)
      rescue Zizek::Failure => failure
        seen0 = []
        replay = lambda do |test_case|
          seen0 << test_case.__send__(:collect, Zizek::Generators.integers(min: lo, max: hi), 0, nil, "list.element")
          raise "replay"
        end
        test.assert_raises(Zizek::Failure) { Zizek.check(replay, reproduce: failure.blob) }
        test.assert_equal [[expected]], seen0, "draw 0 shrank to #{seen0.inspect} instead of [[expected]]"
        return [failure.blob, true]
      end
      [nil, true]
    when "SHRINK_SET"
      test.assert_equal 6, fields.length, "SHRINK_SET field count"
      lo = fields[0].to_i
      hi = fields[1].to_i
      threshold = fields[2].to_i
      seed = fields[3].to_i
      examples = fields[4].to_i
      expected = fields[5].to_i
      property = lambda do |test_case|
        draw0 = test_case.__send__(:collect_unique, Zizek::Generators.integers(min: lo, max: hi), nil, 0, nil, "set.element")
        raise "declared failure" if draw0.any? { |value| value >= threshold }
      end
      begin
        Zizek.check(property, examples: examples, max_rejections: 1000, seed: seed)
      rescue Zizek::Failure => failure
        seen0 = []
        replay = lambda do |test_case|
          seen0 << test_case.__send__(:collect_unique, Zizek::Generators.integers(min: lo, max: hi), nil, 0, nil, "set.element")
          raise "replay"
        end
        test.assert_raises(Zizek::Failure) { Zizek.check(replay, reproduce: failure.blob) }
        test.assert_equal [[expected]], seen0, "draw 0 shrank to #{seen0.inspect} instead of [[expected]]"
        return [failure.blob, true]
      end
      [nil, true]
    when "SHRINK_CLONE"
      test.assert_equal 4, fields.length, "SHRINK_CLONE field count"
      hi = fields[0].to_i
      threshold = fields[1].to_i
      seed = fields[2].to_i
      examples = fields[3].to_i
      property = lambda do |test_case|
        draw0 = test_case.integer(0, hi)
        draw1 = test_case.clone_stream.integer(0, hi)
        draw2 = test_case.integer(0, hi)
        raise "declared failure" if draw1 >= threshold
      end
      begin
        Zizek.check(property, examples: examples, max_rejections: 1000, seed: seed)
      rescue Zizek::Failure => failure
        seen0 = []
        seen1 = []
        seen2 = []
        replay = lambda do |test_case|
          seen0 << test_case.integer(0, hi)
          seen1 << test_case.clone_stream.integer(0, hi)
          seen2 << test_case.integer(0, hi)
          raise "replay"
        end
        test.assert_raises(Zizek::Failure) { Zizek.check(replay, reproduce: failure.blob) }
        test.assert_equal [0], seen0, "draw 0 shrank to #{seen0.inspect} instead of [0]"
        test.assert_equal [threshold], seen1, "draw 1 shrank to #{seen1.inspect} instead of [threshold]"
        test.assert_equal [0], seen2, "draw 2 shrank to #{seen2.inspect} instead of [0]"
        return [failure.blob, true]
      end
      [nil, true]
    when "SHRINK_DUPLICATE"
      test.assert_equal 5, fields.length, "SHRINK_DUPLICATE field count"
      lo = fields[0].to_i
      hi = fields[1].to_i
      seed = fields[2].to_i
      examples = fields[3].to_i
      expected = fields[4].to_i
      property = lambda do |test_case|
        draw0 = test_case.integer(lo, hi)
        draw1 = test_case.integer(lo, hi)
        raise "declared failure" if draw0 == draw1 && draw0 != 0
      end
      begin
        Zizek.check(property, examples: examples, max_rejections: 1000, seed: seed)
      rescue Zizek::Failure => failure
        seen0 = []
        seen1 = []
        replay = lambda do |test_case|
          seen0 << test_case.integer(lo, hi)
          seen1 << test_case.integer(lo, hi)
          raise "replay"
        end
        test.assert_raises(Zizek::Failure) { Zizek.check(replay, reproduce: failure.blob) }
        test.assert_equal [expected], seen0, "draw 0 shrank to #{seen0.inspect} instead of [expected]"
        test.assert_equal [expected], seen1, "draw 1 shrank to #{seen1.inspect} instead of [expected]"
        return [failure.blob, true]
      end
      [nil, true]
    when "SHRINK_PAIR"
      test.assert_equal 7, fields.length, "SHRINK_PAIR field count"
      lo = fields[0].to_i
      hi = fields[1].to_i
      gap = fields[2].to_i
      seed = fields[3].to_i
      examples = fields[4].to_i
      expected_first = fields[5].to_i
      expected_second = fields[6].to_i
      property = lambda do |test_case|
        draw0 = test_case.integer(lo, hi)
        draw1 = test_case.integer(lo, hi)
        raise "declared failure" if draw0 - draw1 == gap
      end
      begin
        Zizek.check(property, examples: examples, max_rejections: 1000, seed: seed)
      rescue Zizek::Failure => failure
        seen0 = []
        seen1 = []
        replay = lambda do |test_case|
          seen0 << test_case.integer(lo, hi)
          seen1 << test_case.integer(lo, hi)
          raise "replay"
        end
        test.assert_raises(Zizek::Failure) { Zizek.check(replay, reproduce: failure.blob) }
        test.assert_equal [expected_first], seen0, "draw 0 shrank to #{seen0.inspect} instead of [expected_first]"
        test.assert_equal [expected_second], seen1, "draw 1 shrank to #{seen1.inspect} instead of [expected_second]"
        return [failure.blob, true]
      end
      [nil, true]
    when "ALWAYS_SHRINK"
      test.assert_equal 6, fields.length, "ALWAYS_SHRINK field count"
      lo = fields[0].to_i
      hi = fields[1].to_i
      threshold = fields[2].to_i
      seed = fields[3].to_i
      examples = fields[4].to_i
      expected = fields[5].to_i
      property = lambda do |test_case|
        draw0 = test_case.integer(lo, hi)
        test_case.always("stays small", draw0 < threshold)
      end
      begin
        Zizek.check(property, examples: examples, max_rejections: 1000, seed: seed)
      rescue Zizek::Failure => failure
        seen0 = []
        replay = lambda do |test_case|
          seen0 << test_case.integer(lo, hi)
          raise "replay"
        end
        test.assert_raises(Zizek::Failure) { Zizek.check(replay, reproduce: failure.blob) }
        test.assert_equal [expected], seen0, "draw 0 shrank to #{seen0.inspect} instead of [expected]"
        return [failure.blob, true]
      end
      [nil, true]
    when "SHRINK_REORDER"
      test.assert_equal 6, fields.length, "SHRINK_REORDER field count"
      lo = fields[0].to_i
      hi = fields[1].to_i
      first = fields[2].to_i
      second = fields[3].to_i
      seed = fields[4].to_i
      examples = fields[5].to_i
      property = lambda do |test_case|
        draw0 = test_case.__send__(:collect, Zizek::Generators.integers(min: lo, max: hi), 0, nil, "list.element")
        raise "declared failure" if draw0.uniq.sort == [first, second].uniq.sort
      end
      begin
        Zizek.check(property, examples: examples, max_rejections: 1000, seed: seed)
      rescue Zizek::Failure => failure
        seen0 = []
        replay = lambda do |test_case|
          seen0 << test_case.__send__(:collect, Zizek::Generators.integers(min: lo, max: hi), 0, nil, "list.element")
          raise "replay"
        end
        test.assert_raises(Zizek::Failure) { Zizek.check(replay, reproduce: failure.blob) }
        test.assert_equal [[first, second]], seen0, "draw 0 shrank to #{seen0.inspect} instead of [[first, second]]"
        return [failure.blob, true]
      end
      [nil, true]
    when "SHRINK_TEXT"
      test.assert_equal 7, fields.length, "SHRINK_TEXT field count"
      alphabet = fields[0]
      min_size = fields[1].to_i
      max_size = fields[2].to_i
      threshold = fields[3].to_i
      seed = fields[4].to_i
      examples = fields[5].to_i
      expected = fields[6]
      generator0 = Zizek::Generators.text.min_size(min_size).max_size(max_size)
      generator0 = generator0.alphabet(alphabet) unless alphabet == "-"
      property = lambda do |test_case|
        draw0 = test_case.draw(generator0)
        raise "declared failure" if draw0.length >= threshold
      end
      begin
        Zizek.check(property, examples: examples, max_rejections: 1000, seed: seed)
      rescue Zizek::Failure => failure
        seen0 = []
        replay = lambda do |test_case|
          seen0 << test_case.draw(generator0)
          raise "replay"
        end
        test.assert_raises(Zizek::Failure) { Zizek.check(replay, reproduce: failure.blob) }
        test.assert_equal [expected], seen0, "draw 0 did not shrink to the declared text"
        return [failure.blob, true]
      end
      [nil, true]
    when "SHRINK_CHARS"
      test.assert_equal 5, fields.length, "SHRINK_CHARS field count"
      alphabet = fields[0]
      simplest = fields[1]
      expected = fields[2]
      seed = fields[3].to_i
      examples = fields[4].to_i
      generator0 = Zizek::Generators.text.min_size(2).max_size(5)
      generator0 = generator0.alphabet(alphabet) unless alphabet == "-"
      property = lambda do |test_case|
        draw0 = test_case.draw(generator0)
        raise "declared failure" if draw0.chars.tally.any? { |character, count| count > 1 && character != simplest }
      end
      begin
        Zizek.check(property, examples: examples, max_rejections: 2000, seed: seed)
      rescue Zizek::Failure => failure
        seen0 = []
        replay = lambda do |test_case|
          seen0 << test_case.draw(generator0)
          raise "replay"
        end
        test.assert_raises(Zizek::Failure) { Zizek.check(replay, reproduce: failure.blob) }
        test.assert_equal [expected], seen0, "draw 0 did not shrink to the declared text"
        return [failure.blob, true]
      end
      [nil, true]
    when "UNIQUE_EXHAUSTED"
      test.assert_equal 5, fields.length, "UNIQUE_EXHAUSTED field count"
      lo = fields[0].to_i
      hi = fields[1].to_i
      min_size = fields[2].to_i
      seed = fields[3].to_i
      examples = fields[4].to_i
      property = lambda do |test_case|
        draw0 = test_case.__send__(:collect_unique, Zizek::Generators.integers(min: lo, max: hi), nil, min_size, nil, "set.element")
        raise "declared failure" if draw0.all? { |value| value >= lo }
      end
      begin
        Zizek.check(property, examples: examples, max_rejections: 1000, seed: seed)
        test.flunk "declared rejecting case completed successfully"
      rescue Zizek::TooManyRejections, Zizek::FailedHealthCheck
        return [nil, true]
      rescue Zizek::Failure => failure
        test.flunk "declared rejecting case reported a counterexample: #{failure}"
      end
    when "REPRODUCE_FAILS"
      test.assert_equal 4, fields.length, "REPRODUCE_FAILS field count"
      blob = fields[0]
      lo = fields[1].to_i
      hi = fields[2].to_i
      expected = fields[3].to_i
      seen0 = []
      property = lambda do |test_case|
        draw0 = test_case.integer(lo, hi)
        seen0 << draw0
        raise "declared failure" if draw0 <= hi
      end
      test.assert_raises(Zizek::Failure) { Zizek.check(property, reproduce: blob) }
      test.assert_equal [expected], seen0, "portable failure replayed #{seen0.inspect}"
      return [nil, true]
    when "REPRODUCE_PASSES"
      test.assert_equal 3, fields.length, "REPRODUCE_PASSES field count"
      blob = fields[0]
      lo = fields[1].to_i
      hi = fields[2].to_i
      property = lambda do |test_case|
        draw0 = test_case.integer(lo, hi)
        raise "declared failure" if draw0 >= hi
      end
      test.assert_raises(Zizek::InvalidReplay) { Zizek.check(property, reproduce: blob) }
      return [nil, true]
    when "PUN_REPORT"
      test.assert_equal 4, fields.length, "PUN_REPORT field count"
      blob = fields[0]
      lo = fields[1].to_i
      hi = fields[2].to_i
      expected_puns = fields[3].to_i
      property = lambda do |test_case|
        draw0 = test_case.integer(lo, hi)
        raise "declared failure" if draw0 <= hi
      end
      failure = test.assert_raises(Zizek::Failure) { Zizek.check(property, reproduce: blob) }
      test.assert_equal expected_puns, failure.puns, "reported #{failure.puns} puns, want expected_puns"
      test.assert_equal expected_puns != 0, failure.message.include?("warning:"), failure.message
      return [nil, true]
    when "SOMETIMES_MISSED"
      test.assert_equal 5, fields.length, "SOMETIMES_MISSED field count"
      lo = fields[0].to_i
      hi = fields[1].to_i
      threshold = fields[2].to_i
      seed = fields[3].to_i
      examples = fields[4].to_i
      property = lambda do |test_case|
        draw0 = test_case.integer(lo, hi)
        test_case.sometimes("above threshold", draw0 > threshold)
      end
      missed = test.assert_raises(Zizek::FailedCoverage) do
        Zizek.check(property, examples: examples, max_rejections: 1000, seed: seed)
      end
      test.assert_equal "above threshold", missed.label
      test.assert_equal 0, missed.observed
      test.assert_equal examples, missed.valid
      return [nil, true]
    when "REQUIRE_MISSED"
      test.assert_equal 1, fields.length, "REQUIRE_MISSED field count"
      examples = fields[0].to_i
      property = lambda do |test_case|
        draw0 = test_case.integer(0, 0)
        raise "declared failure" if draw0 >= 1
      end
      missed = test.assert_raises(Zizek::FailedCoverage) do
        Zizek.check(property, examples: examples, max_rejections: 1000, seed: 1, must_cover: [Zizek::Coverage.new("unreached")])
      end
      test.assert_equal "unreached", missed.label
      test.assert_equal 0, missed.observed
      test.assert_equal examples, missed.valid
      return [nil, true]
    when "COVER_RATE"
      test.assert_equal 2, fields.length, "COVER_RATE field count"
      examples = fields[0].to_i
      percent = fields[1].to_i
      attempts = 0
      property = lambda do |test_case|
        draw0 = test_case.integer(0, 0)
        attempts += 1
        held = attempts == 1
        test_case.cover("first example", held, percent: percent)
        test_case.cover("first example", held, percent: percent)
      end
      missed = test.assert_raises(Zizek::FailedCoverage) do
        Zizek.check(property, examples: examples, max_rejections: 1000, seed: 1)
      end
      test.assert_equal "first example", missed.label
      test.assert_equal 1, missed.observed
      test.assert_equal examples, missed.valid
      return [nil, true]
    when "COVER_STEERS"
      test.assert_equal 8, fields.length, "COVER_STEERS field count"
      lo = fields[0].to_i
      hi = fields[1].to_i
      floor = fields[2].to_i
      copies = fields[3].to_i
      percent = fields[4].to_i
      seed = fields[5].to_i
      examples = fields[6].to_i
      min_observed = fields[7].to_i
      property = lambda do |test_case|
        draw0 = test_case.__send__(:collect, Zizek::Generators.integers(min: lo, max: hi), 0, nil, "list.element")
        test_case.cover("repeat", draw0.any? { |value| value >= floor && draw0.count(value) >= copies }, percent: percent)
      end
      missed = test.assert_raises(Zizek::FailedCoverage) do
        Zizek.check(property, examples: examples, max_rejections: 1000, seed: seed)
      end
      test.assert_equal "repeat", missed.label
      test.assert_operator missed.observed, :>=, min_observed
      test.assert_equal examples, missed.valid
      return [nil, true]
    when "RARE_STEERS"
      test.assert_equal 7, fields.length, "RARE_STEERS field count"
      lo = fields[0].to_i
      hi = fields[1].to_i
      floor = fields[2].to_i
      copies = fields[3].to_i
      percent = fields[4].to_i
      seed = fields[5].to_i
      examples = fields[6].to_i
      property = lambda do |test_case|
        draw0 = test_case.__send__(:collect, Zizek::Generators.integers(min: lo, max: hi), 0, nil, "list.element")
        test_case.cover("repeat", draw0.any? { |value| value >= floor && draw0.count(value) >= copies }, percent: percent)
      end
      Zizek.check(property, examples: examples, max_rejections: 1000, seed: seed)
      return [nil, true]
    when "FLAKY_FAILURE"
      test.assert_equal 4, fields.length, "FLAKY_FAILURE field count"
      lo = fields[0].to_i
      hi = fields[1].to_i
      seed = fields[2].to_i
      examples = fields[3].to_i
      executions = 0
      property = lambda do |test_case|
        test_case.integer(lo, hi)
        executions += 1
        raise "failed on the first execution" if executions == 1
      end
      flaky = test.assert_raises(Zizek::Flaky) do
        Zizek.check(property, examples: examples, max_rejections: 1000, seed: seed)
      end
      test.assert_equal "failed on the first execution", flaky.property_cause.message
      test.assert_includes flaky.message, "flaky"
      test.assert_includes flaky.message, "failed on the first execution"
      return [flaky.blob, true]
    when "STEER_KEEPS_RANDOM"
      test.assert_equal 6, fields.length, "STEER_KEEPS_RANDOM field count"
      lo = fields[0].to_i
      hi = fields[1].to_i
      percent = fields[2].to_i
      seed = fields[3].to_i
      examples = fields[4].to_i
      min_observed = fields[5].to_i
      property = lambda do |test_case|
        draw0 = test_case.__send__(:collect, Zizek::Generators.integers(min: lo, max: hi), 0, nil, "list.element")
        test_case.cover("bucket #{draw0[0] % 10}", true) unless draw0.empty?
        test_case.cover("empty", draw0.empty?, percent: percent)
      end
      missed = test.assert_raises(Zizek::FailedCoverage) do
        Zizek.check(property, examples: examples, max_rejections: 1000, seed: seed)
      end
      test.assert_equal "empty", missed.label
      test.assert_operator missed.observed, :>=, min_observed
      test.assert_equal examples, missed.valid
      return [nil, true]
    else
      [nil, false]
    end
  end
end
