# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "zizek"
require_relative "test_api_visibility"
require_relative "drawops_gen"
require_relative "databasecases_gen"
require_relative "shellcases_gen"
require_relative "../examples/ledger"
require_relative "../examples/queue"
require_relative "../examples/roundtrip"
require_relative "../examples/tour"
require_relative "../examples/hypothesis_quickstart"
require_relative "../examples/min_stack"
require_relative "../examples/stack"
require_relative "../examples/die_hard"
require_relative "../examples/multi"
require_relative "../examples/coverage_assertions"
require_relative "../examples/keyed_draws"
require_relative "../examples/database_workflow"
require_relative "../examples/combinators"

class ZizekTest < Minitest::Test
  CROSS_LANGUAGE_INTEGER_FIVE = "AAEAAAAACgEAAAAF"
  # An explicit shrink_towards above max must clamp to max, not to min. Go and
  # Zig used to fold this together with the "no target given" default and
  # clamped to min instead.
  CROSS_LANGUAGE_CLAMPED_TARGET = "AAEAAAAACgEAAAAK"
  CROSS_LANGUAGE_FLOAT_ONE = "AAEAAAACAAAAAAAA8D8="

  def test_float_shrinks_and_replays_portably
    seen = []
    property = lambda do |test_case|
      value = test_case.draw(
        Zizek::Generators.floats.min_value(0.0).max_value(10.0)
      )
      seen << value
      raise "float must be less than one" if value >= 1.0
    end
    failure = assert_raises(Zizek::Failure) do
      Zizek.check(property, examples: 300, seed: 1)
    end
    assert_equal CROSS_LANGUAGE_FLOAT_ONE, failure.blob
    seen.clear
    assert_raises(Zizek::Failure) do
      Zizek.check(property, reproduce: failure.blob)
    end
    assert_equal [1.0], seen
  end

  # Runs a passing property drawing per_case floats from generator in each of
  # examples cases, and returns every value drawn.
  def collect_floats(generator, per_case:, examples:)
    drawn = []
    property = lambda do |test_case|
      per_case.times { drawn << test_case.draw(generator) }
    end
    Zizek.check(property, examples: examples, seed: 1)
    drawn
  end

  # Raw bit patterns essentially never land in a narrow range, so the old
  # draw fell back to the bounds: floats(1000, 1001) produced only the two
  # endpoints. The default draw now interpolates across the range half the
  # time.
  def test_bounded_floats_reach_the_interior
    narrow = collect_floats(
      Zizek::Generators.floats.min_value(1000.0).max_value(1001.0), per_case: 1, examples: 300
    )
    assert(narrow.all? { |value| value >= 1000.0 && value <= 1001.0 })
    assert_operator narrow.uniq.length, :>, 100

    unit = collect_floats(
      Zizek::Generators.floats.min_value(0.0).max_value(1.0), per_case: 10, examples: 600
    )
    interior = unit.count { |value| value >= 0.25 && value <= 0.75 }.fdiv(unit.length)
    assert_operator interior, :>=, 0.20, "#{(interior * 100).round(1)}% of #{unit.length} draws interior"
  end

  def test_unbounded_floats_still_reach_special_values
    drawn = collect_floats(
      Zizek::Generators.floats.allow_nan(true).allow_infinity(true), per_case: 4, examples: 500
    )
    assert drawn.any?(&:nan?), "no NaN"
    bits = drawn.map { |value| [value].pack("E") }.uniq
    [Float::INFINITY, -Float::INFINITY, 0.0, -0.0].each do |special|
      assert_includes bits, [special].pack("E"), "never drew #{special}"
    end

    finite = collect_floats(Zizek::Generators.floats, per_case: 4, examples: 500)
    assert(finite.all?(&:finite?))
    assert_includes finite, 0.0
  end

  def test_failure_shrinks_and_replays
    seen = []
    property = lambda do |test_case|
      value = test_case.integer(-100, 100)
      seen << value
      raise "too large" unless value < 5
    end

    failure = assert_raises(Zizek::Failure) { Zizek.check(property, examples: 200, seed: 1) }
    seen.clear
    assert_raises(Zizek::Failure) { Zizek.check(property, reproduce: failure.blob) }
    assert_equal [5], seen
  end

  class BugA < StandardError; end

  # A run that discovers one bug must not report a counterexample for another
  # one it stumbled into while shrinking.
  def test_shrinking_stays_on_the_bug_that_was_found
    (1..3).each do |seed|
      found = nil
      property = lambda do |test_case|
        value = test_case.integer(0, 100)
        if value > 50
          found ||= "A"
          raise BugA, "bug A"
        end
        if value == 7
          found ||= "B"
          raise "bug B"
        end
      end
      begin
        Zizek.check(property, examples: 50, seed: seed)
      rescue Zizek::Failure => failure
        assert_equal BugA, failure.property_cause.class if found == "A"
      end
    end
  end

  def test_boolean_and_bytes_round_trip
    property = lambda do |test_case|
      enabled = test_case.boolean
      payload = test_case.bytes(0, 4)
      raise "enabled payload" if enabled && !payload.empty?
    end
    failure = assert_raises(Zizek::Failure) { Zizek.check(property, examples: 200, seed: 7) }
    assert_raises(Zizek::Failure) { Zizek.check(property, reproduce: failure.blob) }
  end

  # The catalogue combinators, pinned across every package that has them.
  # just and one_of's chosen branch record no choice of their own, and
  # sampled_from/one_of record exactly one integer each, so the blob is the
  # check that all four shells compose them identically.
  CROSS_LANGUAGE_CATALOGUE = "AAMAAAABAQAKAQAAAAIACgEAAAAA"

  def catalogue_draw(test_case)
    g = Zizek::Generators
    [
      test_case.draw(g.booleans),
      test_case.draw(g.sampled_from([2, 3, 5, 7])),
      test_case.draw(g.one_of(g.just(0), g.integers.min_value(1).max_value(9)))
    ]
  end

  def test_catalogue_generators_shrink_and_replay_portably
    property = lambda do |test_case|
      flag, pick, extra = catalogue_draw(test_case)
      raise "flagged and large" if flag && pick >= 5
    end
    failure = assert_raises(Zizek::Failure) { Zizek.check(property, examples: 300, seed: 1) }
    assert_equal CROSS_LANGUAGE_CATALOGUE, failure.blob

    seen = []
    replay = lambda do |test_case|
      seen << catalogue_draw(test_case)
      raise "replay"
    end
    assert_raises(Zizek::Failure) { Zizek.check(replay, reproduce: failure.blob) }
    # one_of shrinks towards its first branch, so the minimal example takes
    # just(0) rather than paying for an integer draw.
    assert_equal [[true, 5, 0]], seen
  end

  def test_map_and_filter_compose_without_recording_a_choice
    g = Zizek::Generators
    doubled = g.integers.min_value(0).max_value(10).map { |value| value * 2 }
    evens = g.integers.min_value(0).max_value(20).filter(&:even?)
    drawn = []
    Zizek.check(->(test_case) { drawn << [test_case.draw(doubled), test_case.draw(evens)] },
                examples: 50, seed: 3)
    assert(drawn.all? { |a, b| a.even? && b.even? })
  end

  # flat_map, pinned across every package that has it. The drawn scale decides
  # the inner generator's bounds, so the two draws only make sense together;
  # the blob is the check that all nine shells compose and shrink the bind
  # identically. The scale rescues the inner draw's validity when it is
  # lowered, so the minimum is reachable from whatever example a language's
  # RNG finds first — the property a pinned row requires.
  CROSS_LANGUAGE_FLAT_MAP = "AXicY2IAAi5GBjjFCgABCgAe"

  def flat_map_scaled(g)
    g.integers(0..3).flat_map do |scale|
      g.integers((scale * 10)..(scale * 10 + 100))
    end
  end

  def test_flat_map_shrinks_and_replays_portably
    g = Zizek::Generators
    property = lambda do |test_case|
      raise "value reached 5" if test_case.draw(flat_map_scaled(g)) >= 5
    end
    failure = assert_raises(Zizek::Failure) { Zizek.check(property, examples: 300, seed: 1) }
    assert_equal CROSS_LANGUAGE_FLAT_MAP, failure.blob

    seen = []
    replay = lambda do |test_case|
      seen << test_case.draw(flat_map_scaled(g))
      raise "replay"
    end
    assert_raises(Zizek::Failure) { Zizek.check(replay, reproduce: failure.blob) }
    # The minimal example takes scale 0, then the smallest value the property
    # notices.
    assert_equal [5], seen
  end

  def test_flat_map_lengths_move_with_the_list
    g = Zizek::Generators
    lists_of = g.integers(0..3).flat_map do |length|
      g.lists(g.integers(0..100), min: length, max: length)
    end
    property = lambda do |test_case|
      values = test_case.draw(lists_of)
      raise "element reached 5" if values.any? { |value| value >= 5 }
    end
    failure = assert_raises(Zizek::Failure) { Zizek.check(property, examples: 300, seed: 1) }

    seen = []
    replay = lambda do |test_case|
      seen << test_case.draw(lists_of)
      raise "replay"
    end
    assert_raises(Zizek::Failure) { Zizek.check(replay, reproduce: failure.blob) }
    # Which length the search settles on depends on where generation started —
    # the source integer cannot shrink without the elements it paid for — so
    # the invariant is the failure's shape, not an exact stream.
    assert_equal 1, seen.length
    assert seen.first.any? { |value| value >= 5 }
    assert seen.first.all? { |value| value <= 5 }
  end

  def test_flat_map_coerces_a_plain_value
    g = Zizek::Generators
    doubled = g.integers(0..5).flat_map { |value| value * 2 }
    drawn = []
    Zizek.check(->(test_case) { drawn << test_case.draw(doubled) }, examples: 20, seed: 2)
    assert(drawn.all?(&:even?))
  end

  def test_targeting_steers_generation_toward_high_scores
    # With 200 examples the compiled schedule fires the hill climber at 100
    # valid examples; unguided random search hits the failing band in
    # roughly one example per ten thousand.
    property = lambda do |test_case|
      value = test_case.integer(0, 100_000)
      test_case.target(value)
      raise "reached the top" if value >= 99_990
    end
    failure = assert_raises(Zizek::Failure) { Zizek.check(property, examples: 200, seed: 5) }

    seen = []
    replay = lambda do |test_case|
      seen << test_case.integer(0, 100_000)
      raise "replay"
    end
    assert_raises(Zizek::Failure) { Zizek.check(replay, reproduce: failure.blob) }
    assert_equal [99_990], seen
  end

  def test_targeting_climbs_each_label_separately
    # The failing band is reachable only through the *second* label in sorted
    # order, so finding it requires the per-label bookkeeping: "high" is
    # climbed first, discovers nothing, and the climb moves on to "low".
    # (A failure needing both dimensions at their top at once is deliberately
    # not asserted: a lateral +k climb of the other label's draw is undone by
    # the -k pass, upstream and here alike.)
    property = lambda do |test_case|
      low = test_case.integer(0, 20_000)
      high = test_case.integer(0, 20_000)
      test_case.target(low, label: "low")
      test_case.target(high, label: "high")
      raise "low climbed" if low >= 19_990
    end
    failure = assert_raises(Zizek::Failure) { Zizek.check(property, examples: 600, seed: 7) }

    seen = []
    replay = lambda do |test_case|
      seen << [test_case.integer(0, 20_000), test_case.integer(0, 20_000)]
      raise "replay"
    end
    assert_raises(Zizek::Failure) { Zizek.check(replay, reproduce: failure.blob) }
    assert_equal [[19_990, 0]], seen
  end

  def test_target_validates_scores_and_labels
    test_case = Zizek::TestCase.new(rng: Random.new(1))
    test_case.target(3.5)
    error = assert_raises(ArgumentError) { test_case.target(4.0) }
    assert_match(/at most once/, error.message)
    error = assert_raises(ArgumentError) { test_case.target(Float::NAN, label: "other") }
    assert_match(/finite/, error.message)
    test_case.target(1, label: "second")
    assert_equal({ "" => 3.5, "second" => 1.0 }, test_case.__send__(:targets))
  end

  def test_tuples_and_none_draw_in_order
    g = Zizek::Generators
    seen = []
    Zizek.check(->(test_case) { seen << test_case.draw(g.tuples(g.just(1), g.none, g.booleans)) },
                examples: 1)
    assert_equal [[1, nil, false]], seen
  end

  def test_cross_language_blob_fixture
    seen = []
    property = lambda do |test_case|
      seen << test_case.integer(-100, 100)
      raise "always fails"
    end
    assert_raises(Zizek::Failure) { Zizek.check(property, reproduce: CROSS_LANGUAGE_INTEGER_FIVE) }
    assert_equal [5], seen
  end

  def test_assumptions_do_not_count_as_examples
    attempts = 0
    property = lambda do |test_case|
      attempts += 1
      test_case.assume(attempts.even?)
    end
    Zizek.check(property, examples: 3, seed: 11)
    assert_equal 6, attempts
  end

  def test_simplest_probe_uses_choice_simplest_values
    seen = []
    property = lambda do |test_case|
      seen << [
        test_case.integer(5, 10, shrink_towards: 7),
        test_case.boolean,
        test_case.bytes(2, 4),
        test_case.float(1.0, 2.0)
      ]
    end
    Zizek.check(property, examples: 1)
    assert_equal [[7, false, "\x00\x00".b, 1.0]], seen
  end

  def test_large_base_example_health_check_and_suppression
    property = lambda do |test_case|
      4_097.times { test_case.boolean }
    end
    health = assert_raises(Zizek::FailedHealthCheck) do
      Zizek.check(property, examples: 1)
    end
    assert_equal :large_base_example, health.check
    Zizek.check(
      property,
      examples: 1,
      suppress_large_base_example: true
    )
  end

  def test_too_slow_health_check_and_suppression
    property = lambda do |test_case|
      test_case.__send__(:generation_us=, 1_000_001)
    end
    health = assert_raises(Zizek::FailedHealthCheck) do
      Zizek.check(property, examples: 1)
    end
    assert_equal :too_slow, health.check
    Zizek.check(property, examples: 1, suppress_too_slow: true)
  end

  def test_too_many_rejections
    failure = assert_raises(Zizek::TooManyRejections) do
      Zizek.check(->(test_case) { test_case.assume(false) }, examples: 1, max_rejections: 2)
    end
    assert_equal 3, failure.rejections
    assert_equal 2, failure.limit
  end

  def test_filter_too_much_health_check_and_suppression
    property = ->(test_case) { test_case.assume(false) }
    health = assert_raises(Zizek::FailedHealthCheck) do
      Zizek.check(property, examples: 1, suppress_large_base_example: true)
    end
    assert_equal :filter_too_much, health.check

    rejected = assert_raises(Zizek::TooManyRejections) do
      Zizek.check(
        property,
        examples: 1,
        max_rejections: 50,
        suppress_filter_too_much: true
      )
    end
    assert_equal 51, rejected.rejections
  end

  def test_data_too_large_health_check_and_suppression
    attempts = 0
    property = lambda do |test_case|
      attempts += 1
      8_193.times { test_case.boolean } if attempts <= 20
    end
    health = assert_raises(Zizek::FailedHealthCheck) do
      Zizek.check(property, examples: 1, suppress_large_base_example: true)
    end
    assert_equal :data_too_large, health.check

    attempts = 0
    Zizek.check(
      property,
      examples: 1,
      suppress_data_too_large: true,
      suppress_large_base_example: true
    )
    assert_equal 21, attempts
  end

  def test_valid_examples_expand_the_rejection_budget
    attempts = 0
    property = lambda do |test_case|
      attempts += 1
      test_case.assume((attempts % 101).zero?)
    end
    Zizek.check(property, examples: 15, seed: 11, suppress_filter_too_much: true)
    assert_equal 1_515, attempts
  end

  def test_rejected_shrink_candidate_is_not_failure
    property = lambda do |test_case|
      value = test_case.integer(0, 100)
      test_case.assume(value >= 5)
      raise "accepted value fails"
    end
    failure = assert_raises(Zizek::Failure) { Zizek.check(property, examples: 100, seed: 3) }
    replayed = []
    replay = lambda do |test_case|
      value = test_case.integer(0, 100)
      replayed << value
      test_case.assume(value >= 5)
      raise "accepted value fails"
    end
    assert_raises(Zizek::Failure) { Zizek.check(replay, reproduce: failure.blob) }
    assert_equal [5], replayed
  end

  def test_replay_puns_across_choice_kinds
    seen = []
    property = lambda do |test_case|
      seen << test_case.boolean
      raise "always fails"
    end
    assert_raises(Zizek::Failure) { Zizek.check(property, reproduce: CROSS_LANGUAGE_INTEGER_FIVE) }
    assert_equal [true], seen
  end

  def test_forced_draw_skips_replay_position
    raw = Zizek.const_get(:Core).choice_list_header(2)
    raw += Zizek.const_get(:Core).serialize_integer_choice(Zizek.const_get(:Shell).signed_bytes(5))
    raw += Zizek.const_get(:Core).serialize_integer_choice(Zizek.const_get(:Shell).signed_bytes(7))
    blob = Zizek.const_get(:Core).raw_failure_encode(raw)
    seen = []
    property = lambda do |test_case|
      seen << test_case.__send__(:forced_integer, 99)
      seen << test_case.integer(0, 10)
      raise "always fails"
    end
    assert_raises(Zizek::Failure) { Zizek.check(property, reproduce: blob) }
    assert_equal [99, 7], seen
  end

  def test_replay_overrun_is_not_failure
    property = lambda do |test_case|
      test_case.integer(0, 10)
      test_case.integer(0, 10)
      raise "unreachable"
    end
    assert_raises(Zizek::ReplayOverrun) do
      Zizek.check(property, reproduce: CROSS_LANGUAGE_INTEGER_FIVE)
    end
  end

  def test_nested_choice_spans
    captured = []
    property = lambda do |test_case|
      assert_equal 0, test_case.start_span("outer")
      test_case.integer(0, 10)
      assert_equal 1, test_case.start_span("inner")
      test_case.boolean
      test_case.stop_span(discarded: true)
      test_case.bytes(0, 2)
      test_case.stop_span
      captured.concat(test_case.__send__(:spans))
    end
    Zizek.check(property, examples: 1, seed: 17)
    assert_equal(
      [
        [0, 3, "outer", 0, nil, false],
        [1, 2, "inner", 1, 0, true]
      ],
      captured.map { |span| [span.start, span.finish, span.label, span.depth, span.parent, span.discarded] }
    )
  end

  def test_list_shrinks_by_deleting_elements
    element = Zizek::Generators.integers.min_value(0).max_value(1000)
    property = lambda do |test_case|
      values = test_case.draw(Zizek::Generators.lists(element))
      raise "sum too large" unless values.sum < 50
    end
    failure = assert_raises(Zizek::Failure) { Zizek.check(property, examples: 200, seed: 7) }
    seen = []
    replay = lambda do |test_case|
      seen << test_case.draw(Zizek::Generators.lists(element))
      raise "replay"
    end
    assert_raises(Zizek::Failure) { Zizek.check(replay, reproduce: failure.blob) }
    # Not merely "shorter": the one element left is the smallest that fails.
    assert_equal [[50]], seen
  end

  def test_list_deletes_an_element_from_the_middle
    element = Zizek::Generators.integers.min_value(0).max_value(10)
    property = lambda do |test_case|
      values = test_case.draw(Zizek::Generators.lists(element))
      raise "found three" if values.include?(3)
    end
    failure = assert_raises(Zizek::Failure) { Zizek.check(property, examples: 500, seed: 3) }
    seen = []
    replay = lambda do |test_case|
      seen << test_case.draw(Zizek::Generators.lists(element))
      raise "replay"
    end
    assert_raises(Zizek::Failure) { Zizek.check(replay, reproduce: failure.blob) }
    # Every element around the interesting one has to be deletable, not only
    # the trailing ones a truncating shrinker can drop.
    assert_equal [[3]], seen
  end

  def test_list_respects_its_size_bounds
    element = Zizek::Generators.integers.min_value(0).max_value(10)
    lengths = []
    property = lambda do |test_case|
      values = test_case.draw(Zizek::Generators.lists(element).min_size(2).max_size(4))
      lengths << values.length
    end
    Zizek.check(property, examples: 200, seed: 5)
    assert_empty lengths.reject { |length| (2..4).cover?(length) }
    assert_operator lengths.uniq.length, :>, 1, "bounded list never varied its length"
  end

  def test_fixed_size_list_draws_no_length_choice
    element = Zizek::Generators.integers.min_value(0).max_value(10)
    captured = []
    property = lambda do |test_case|
      test_case.draw(Zizek::Generators.lists(element).min_size(2).max_size(2))
      captured.concat(test_case.__send__(:draws))
    end
    Zizek.check(property, examples: 1, seed: 1)
    # Coinciding bounds decide nothing, so the stream holds the two elements
    # and no "another element?" booleans at all.
    assert_equal %i[integer integer], captured.map(&:kind)
  end

  def test_list_elements_are_recorded_as_spans
    element = Zizek::Generators.integers.min_value(0).max_value(3)
    captured = []
    property = lambda do |test_case|
      test_case.__send__(:collect, element, 2, 2)
      captured.concat(test_case.__send__(:spans))
    end
    Zizek.check(property, examples: 1, seed: 1)
    # One span per element plus the empty span of the iteration that stopped;
    # each element span is exactly the range deletion removes.
    assert_equal(
      [[0, 1, false], [1, 2, false], [2, 2, true]],
      captured.map { |span| [span.start, span.finish, span.discarded] }
    )
  end

  def test_set_elements_are_always_distinct
    element = Zizek::Generators.integers.min_value(0).max_value(6)
    sizes = []
    property = lambda do |test_case|
      values = test_case.draw(Zizek::Generators.sets(element, max: 6))
      sizes << values.length
    end
    Zizek.check(property, examples: 300, seed: 3)
    # A Set drops repeats silently, so what proves the element loop kept asking
    # after a duplicate is that sets grew past one element at all.
    assert_operator sizes.max, :>, 1, "set never grew past one element"
  end

  def test_duplicate_candidates_are_discarded_not_kept
    # Two distinct values in the range and three requested elements, so the
    # third element is guaranteed to burn its candidates and reject.
    element = Zizek::Generators.integers.min_value(0).max_value(1)
    captured = []
    property = lambda do |test_case|
      test_case.__send__(:collect_unique, element, nil, 0, 3)
      captured.concat(test_case.__send__(:spans))
    end
    Zizek.check(property, examples: 1, seed: 1)
    assert captured.any? { |span| span.discarded && span.finish > span.start },
           "a duplicate candidate left no discarded span behind"
  end

  def test_unsatisfiable_uniqueness_rejects_rather_than_hanging
    # Four distinct values cannot come out of a two-value range.
    element = Zizek::Generators.integers.min_value(0).max_value(1)
    property = lambda do |test_case|
      test_case.draw(Zizek::Generators.sets(element, min: 4))
      raise "unreachable"
    end
    assert_raises(Zizek::TooManyRejections, Zizek::FailedHealthCheck) do
      Zizek.check(property, examples: 50, seed: 1)
    end
  end

  def test_reject_action_matches_the_generated_rule
    # The three actions, read straight off the compiled decision so the shell's
    # branch names cannot drift from what they dispatch on.
    assert_equal Zizek::TestCase.const_get(:REJECT_RETRY), Zizek.const_get(:Core).many_reject_action(1, 0, 0)
    assert_equal Zizek::TestCase.const_get(:REJECT_STOP), Zizek.const_get(:Core).many_reject_action(4, 0, 0)
    assert_equal Zizek::TestCase.const_get(:REJECT_INVALID), Zizek.const_get(:Core).many_reject_action(4, 0, 1)
    assert_equal Zizek::TestCase.const_get(:REJECT_RETRY), Zizek.const_get(:Core).many_reject_action(4, 2, 0)
    assert_equal 3, Zizek.const_get(:Core).many_rejection_budget(0)
  end

  def test_hash_keys_are_distinct_and_values_are_free
    keys = Zizek::Generators.integers.min_value(0).max_value(3)
    values = Zizek::Generators.integers.min_value(0).max_value(1)
    seen = []
    property = lambda do |test_case|
      seen << test_case.draw(Zizek::Generators.hashes(keys, values, max: 4))
    end
    Zizek.check(property, examples: 200, seed: 4)
    assert seen.any? { |mapping| mapping.length > 1 }, "hash never held more than one entry"
    # Values repeat freely — uniqueness is judged on the key alone.
    assert seen.any? { |mapping| mapping.length > 1 && mapping.values.uniq.length < mapping.length },
           "no hash ever repeated a value, so the key predicate is too wide"
  end

  def test_unique_by_judges_distinctness_on_the_key
    element = Zizek::Generators.integers.min_value(0).max_value(9)
    seen = []
    property = lambda do |test_case|
      values = test_case.draw(
        Zizek::Generators.lists(element, max: 6, unique_by: ->(value) { value % 3 })
      )
      seen << values
    end
    Zizek.check(property, examples: 200, seed: 6)
    seen.each do |values|
      residues = values.map { |value| value % 3 }
      assert_equal residues.length, residues.uniq.length, values.inspect
    end
    assert seen.any? { |values| values.length > 1 }
  end

  def test_open_span_closes_on_failure
    captured = []
    property = lambda do |test_case|
      test_case.start_span("open")
      test_case.boolean
      captured << test_case
      raise "boom"
    end
    assert_raises(Zizek::Failure) { Zizek.check(property, examples: 1, seed: 1) }
    assert_equal 1, captured.first.__send__(:spans).length
    assert_equal 1, captured.first.__send__(:spans).first.finish
  end

  def test_forced_choice_has_no_shrink_candidates
    draw = Zizek.const_get(:Draw).new(:integer, "".b, 99, [99, 99, 99], true)
    assert_empty Zizek.const_get(:Shell).candidate_draws(draw)
  end

  def test_sort_key_is_choice_count_first_shortlex
    boolean_draw = lambda do |value, forced = false|
      Zizek.const_get(:Draw).new(
        :boolean,
        Zizek.const_get(:Core).serialize_boolean_choice(value),
        value,
        [],
        forced
      )
    end
    false_draw = boolean_draw.call(false)
    true_draw = boolean_draw.call(true)
    assert Zizek.const_get(:Shell).draws_simpler?([true_draw], [false_draw, false_draw])
    assert Zizek.const_get(:Shell).draws_simpler?([false_draw, true_draw], [true_draw, false_draw])
    refute Zizek.const_get(:Shell).draws_simpler?([true_draw, false_draw], [false_draw, true_draw])
    assert Zizek.const_get(:Shell).draws_simpler?(
      [boolean_draw.call(false, true)],
      [boolean_draw.call(true, true)]
    )
    bytes8 = "\0".b * 8
    bytes9 = "\0".b * 9
    draw8 = Zizek.const_get(:Draw).new(
      :bytes, Zizek.const_get(:Core).serialize_bytes_choice(bytes8), bytes8, [0, 16], false
    )
    draw9 = Zizek.const_get(:Draw).new(
      :bytes, Zizek.const_get(:Core).serialize_bytes_choice(bytes9), bytes9, [0, 16], false
    )
    assert Zizek.const_get(:Shell).draws_simpler?([draw8], [draw9])
    refute Zizek.const_get(:Shell).draws_simpler?([draw9], [draw8])
  end

  def test_biased_integer_finds_boundary
    property = lambda do |test_case|
      raise "found one" if test_case.integer(0, 1_000_000) == 1
    end
    assert_raises(Zizek::Failure) { Zizek.check(property, examples: 5_000, seed: 23) }
  end

  def test_pool_reusable_and_consumed
    property = lambda do |test_case|
      values = Zizek::Stateful.pool(test_case)
      values.add(test_case, "old")
      values.add(test_case, "new")
      assert_includes %w[old new], test_case.draw(values.values_reusable)
      assert_includes %w[old new], test_case.draw(values.values_consumed)
      assert_equal 1, values.length
    end
    Zizek.check(property, examples: 20, seed: 11)
  end

  # Adding to a pool draws a recorded identifier, and every reference replays
  # onto the same value it named when recorded.
  #
  # Adding used to consume no choice at all and a reference used to be a
  # reverse index into the live list, so the pool's whole identity scheme lived
  # in host state the blob never saw. Both halves are now in the stream
  # (hegel-c 0.32.4), which is what this pins: the identifier draws are real
  # entries, and replaying the blob resolves the same variables rather than
  # whatever now sits at those positions.
  def test_pool_add_records_an_identifier_that_replays
    drawn = []
    property = lambda do |test_case|
      values = Zizek::Stateful.pool(test_case)
      %w[a b c].each { |name| values.add(test_case, name) }
      drawn << [
        test_case.draw(values.values_reusable),
        test_case.draw(values.values_reusable)
      ]
      raise "always fails"
    end

    failure = assert_raises(Zizek::Failure) { Zizek.check(property, examples: 1, seed: 5) }
    recorded = drawn.last
    # Three adds and two references: five recorded entries where the old
    # encoding recorded only the two references.
    raw = Zizek.const_get(:Core).raw_failure_decode(failure.blob)
    refute_nil raw
    assert_equal 5, Zizek.const_get(:Core).choice_stream_count(raw)

    drawn.clear
    assert_raises(Zizek::Failure) { Zizek.check(property, reproduce: failure.blob) }
    assert_equal recorded, drawn.last
  end

  # The minimal failure of ThirdA under the continue protocol, and the same
  # failure as the stop protocol recorded it before the decision was inverted.
  STATEFUL_THIRD_A_FAILURE = "AXichYgxCgAACIR0Dfr/dyOC1nNRbEApWU5+mM8ADpIAZA=="
  STATEFUL_THIRD_A_STOP_PROTOCOL = "AXiclcaxDQAACMMwd0Xi/3dh4QCGKG6E2tzywQAOIgBh"
  # ThirdA's failure behind one integer drawn before the machine starts.
  STATEFUL_DRAW_BEFORE_THIRD_A_FAILURE = "AXicfYmxDQAACMLs6uD/56qJTiQwEGgrJsk23PgvwpAGEhwAcA=="

  # One rule that draws one integer: the smallest machine a step count can
  # make large.
  class Pusher < Zizek::Stateful::Machine
    attr_reader :pushed

    def initialize
      @pushed = []
    end

    rule(:push) { |t| @pushed << t.integer(0, 10) }
  end

  # Rule "a" fails on its third run. Both rules draw an integer first, which
  # is what made the legacy stream read back as protocol 2.
  class ThirdA < Zizek::Stateful::Machine
    attr_reader :seen

    def initialize
      @seen = []
    end

    rule(:a) do |t|
      t.integer(0, 10)
      @seen << "a"
      raise "a ran three times" if @seen.count("a") >= 3
    end

    rule(:b) do |t|
      t.integer(0, 10)
      @seen << "b"
    end
  end

  # The rules a ThirdA blob runs, asserting that it fails.
  def replay_third_a(blob)
    machine = nil
    property = lambda do |test_case|
      machine = ThirdA.new
      Zizek::Stateful.run(machine, test_case)
    end
    assert_raises(Zizek::Failure) { Zizek.check(property, reproduce: blob) }
    machine.seen
  end

  def stateful_protocol_of(blob)
    core = Zizek.const_get(:Core)
    raw = core.raw_failure_decode(blob)
    refute_nil raw
    core.stateful_choice_protocol(raw, 4, core.choice_stream_count(raw))
  end

  # The per-step continue decision (hegel-c 0.36.1). The next three tests run
  # with the same constants in every shell's test file, because the shared
  # shell-case table has no way to describe a machine.

  # The simplest value of a continue decision stops. Under the old stop
  # decision the all-simplest probe ran every one of its steps, so a one-rule
  # machine at 5000 steps overran the choice budget and failed the
  # large_base_example health check (upstream #433). With one example the probe
  # is the only case the run executes.
  def test_simplest_probe_runs_one_step_under_a_large_step_count
    counts = []
    property = lambda do |test_case|
      machine = Pusher.new
      Zizek::Stateful.run(machine, test_case, step_count: 5000)
      counts << machine.pushed.length
    end
    Zizek.check(property, examples: 1, seed: 1)
    assert_equal [1], counts
  end

  # A failure the simplest probe cannot reach shrinks and replays. The probe
  # used to record the legacy protocol, which the sniffer reads back as
  # protocol 2 once a rule draws an integer first, so this run failed with
  # "shrunk example no longer fails". Every shell converges on the same
  # three-step stream, so the blob is pinned.
  def test_third_run_failure_shrinks_to_three_steps_and_replays
    property = ->(test_case) { Zizek::Stateful.run(ThirdA.new, test_case) }
    failure = assert_raises(Zizek::Failure) { Zizek.check(property, examples: 100, seed: 1) }
    assert_equal 3, stateful_protocol_of(failure.blob)
    assert_equal STATEFUL_THIRD_A_FAILURE, failure.blob
    assert_equal %w[a a a], replay_third_a(failure.blob)
  end

  # A draw before the machine starts is not read as the machine's own. The
  # protocol sniffer used to read the head of the stream, so the leading
  # integer made a continue-protocol stream look like a stop-protocol one: the
  # replay inverted every decision and stopped after one step, the shrinker
  # reported the failure as flaky, and the blob it printed did not reproduce.
  def test_draw_before_machine_shrinks_and_replays
    machine = nil
    property = lambda do |test_case|
      test_case.integer(0, 10)
      machine = ThirdA.new
      Zizek::Stateful.run(machine, test_case)
    end
    failure = assert_raises(Zizek::Failure) { Zizek.check(property, examples: 100, seed: 1) }
    assert_equal STATEFUL_DRAW_BEFORE_THIRD_A_FAILURE, failure.blob
    assert_raises(Zizek::Failure) { Zizek.check(property, reproduce: failure.blob) }
    assert_equal %w[a a a], machine.seen
  end

  # A continue-protocol blob replays in every shell, and blobs recorded under
  # the stop decision keep their meaning.
  def test_pinned_blobs_of_both_protocols_replay
    [[STATEFUL_THIRD_A_FAILURE, 3], [STATEFUL_THIRD_A_STOP_PROTOCOL, 2]].each do |blob, protocol|
      assert_equal protocol, stateful_protocol_of(blob)
      assert_equal %w[a a a], replay_third_a(blob)
    end
    assert_raises(Zizek::Failure) do
      Zizek.check(LedgerExample.method(:property), reproduce: LedgerExample::PORTABLE_LEDGER_FAILURE)
    end
  end

  def test_ledger_bug_shrinks_to_three_steps
    failure = LedgerExample.find_and_replay_bug
    rendered = failure.message
    assert_includes rendered, "step 1: create_account"
    assert_includes rendered, "step 2: create_account"
    assert_includes rendered, "step 3: transfer"
    refute_includes rendered, "step 4:"
    assert_includes rendered, "transfer 1"
    assert_raises(Zizek::Failure) do
      Zizek.check(LedgerExample.method(:property), reproduce: LedgerExample::PORTABLE_LEDGER_FAILURE)
    end
  end

  def test_roundtrip_example_shrinks_to_one_character
    failure = RoundtripExample.find_and_replay_bug
    assert_includes failure.message, '"0" became ""'
    assert_equal RoundtripExample::PORTABLE_ROUNDTRIP_FAILURE, failure.blob
  end

  def test_out_of_range_shrink_target_clamps_to_the_nearer_bound
    property = lambda do |test_case|
      value = test_case.draw(Zizek::Generators.integers.min_value(0).max_value(10).shrink_towards(99))
      raise "always fails at #{value}"
    end

    failure = assert_raises(Zizek::Failure) { Zizek.check(property, examples: 50, seed: 7) }
    assert_equal "always fails at 10", failure.cause.message
    assert_equal CROSS_LANGUAGE_CLAMPED_TARGET, failure.blob
  end

  def test_tour_example_scenarios
    assert_includes TourExample.shrink_targets.message, "value 701"
    assert_includes TourExample.even_numbers_only.message, "even value 52"
    assert_includes TourExample.flags_and_bytes.message, "compressed=true payload=80"
    assert_equal CROSS_LANGUAGE_FLOAT_ONE, TourExample.bounded_floats.blob
    rejected = TourExample.rejection_limit
    assert_equal [21, 20], [rejected.rejections, rejected.limit]
  end

  def test_queue_example_finds_and_replays_the_off_by_one
    failure = QueueExample.find_and_replay_bug
    assert_includes failure.message, "step 1:"
    assert_includes failure.message, "pop"
    assert_equal QueueExample::PORTABLE_QUEUE_FAILURE, failure.blob
  end

  def test_hypothesis_quickstart_shrinks_to_the_boundary
    failure = HypothesisQuickstartExample.find_and_replay_boundary
    assert_equal "50 is not less than 50", failure.property_cause.message
    assert_equal HypothesisQuickstartExample::SHRUNK_BOUNDARY_FAILURE, failure.blob
  end

  def test_min_stack_finds_the_repeated_minimum_bug
    failure = MinStackExample.find_and_replay_bug
    assert_includes failure.message, "step 1: push"
    assert_includes failure.message, "step 2: push"
    assert_includes failure.message, "step 3: pop"
    refute_includes failure.message, "step 4:"
    assert_equal MinStackExample::SHRUNK_MIN_STACK_FAILURE, failure.blob
  end

  def test_hegel_stack_model_passes
    assert StackExample.verify_stack_model
  end

  def test_die_hard_finds_the_six_step_solution
    failure = DieHardExample.find_and_replay_solution
    assert_includes failure.message, "step 6: pour_big_into_small"
    refute_includes failure.message, "step 7:"
    assert_equal DieHardExample::SHRUNK_DIE_HARD_FAILURE, failure.blob
  end

  def test_multi_preserves_the_selected_failure_origin
    failure = MultiExample.find_and_replay_one_origin
    assert_equal "1338 is not below the edge", failure.property_cause.message
  end

  def test_coverage_example_scenarios
    always = CoverageAssertionsExample.always_shrinks_to_the_boundary
    assert_includes always.message, 'always: "clamped into range" did not hold'
    # The smallest value escaping the broken ceiling is 101 — the blob the
    # README documents for this exact scenario.
    assert_equal "AAEAAAAACgEAAABl", always.blob

    unreachable = CoverageAssertionsExample.unreachable_finds_the_simplest_path
    assert_includes unreachable.message, 'unreachable: "value escaped the clamp" was reached'
    assert_equal always.blob, unreachable.blob

    vacuous = CoverageAssertionsExample.sometimes_fails_the_vacuous_pass
    assert_equal ["saturated at the ceiling", 0, 200], [vacuous.label, vacuous.observed, vacuous.valid]

    rate = CoverageAssertionsExample.cover_reports_the_observed_rate
    assert_equal ["left below the ceiling", 60.0], [rate.label, rate.min_percent]
    assert_operator rate.observed, :<, rate.valid * 60 / 100

    declared = CoverageAssertionsExample.must_cover_catches_the_unregistered_label
    assert_equal "overflow path", declared.label
  end

  def test_keyed_draws_example_survives_the_property_edit
    found, replayed = KeyedDrawsExample.keyed_blob_survives_the_edit
    assert_equal found.blob, replayed.blob
    assert_equal 1, replayed.key_misses
    assert_includes replayed.notes, found.notes.first

    _, overrun = KeyedDrawsExample.positional_blob_breaks_on_the_edit
    assert_instance_of Zizek::ReplayOverrun, overrun
  end

  def test_database_workflow_example_stores_replays_and_collects
    first, second = DatabaseWorkflowExample.run_workflow
    assert_equal first.blob, second.blob
    assert_equal 1, second.examples_run
    assert_equal [[:left, []], [:right, [0]]], first.values
  end

  def test_combinators_example_shrinks_through_the_composition
    request = CombinatorsExample.delete_with_a_body
    assert_includes request.message, 'verb=:delete, path="/a", body="x", retries=0'

    meeting = CombinatorsExample.meeting_across_noon
    assert_equal [[:meeting, [0, 12]]], meeting.values
  end
end


# The shell-level counterpart to the golden vector gate. Every shell runs the
# same table from conformance/shell/shell_cases.tsv, so a behavior that drifts in one
# language fails there rather than in review.
class ShellConformanceTest < Minitest::Test
  # The tables live outside this package: they are shared with the other
  # language packages so a behavior that drifts in one fails here. They are
  # therefore not shipped with it, and this file says so rather than quietly
  # skipping the gate.
  CASES = File.expand_path("../../../conformance/shell/shell_cases.tsv", __dir__)
  # Generated by tools/tracegen from the real Hegel engine, and read as a second
  # table rather than merged into the hand-written one so it stays regenerable.
  TRACE_CASES = File.expand_path("../../../conformance/shell/trace_vectors.tsv", __dir__)

  def shell_cases
    [CASES, TRACE_CASES].flat_map do |path|
      unless File.exist?(path)
        raise "#{path} is missing: the shared conformance tables live in the " \
              "Zizek source tree and are not shipped with this package"
      end

      # Read as UTF-8 explicitly: the KEY_DIGEST rows carry non-ASCII names on
      # purpose, and the default external encoding is the machine's, not the
      # table's.
      File.readlines(path, chomp: true, encoding: "UTF-8")
          .reject { |line| line.empty? || line.start_with?("#") }
          .map { |line| line.split("\t") }
    end
  end

  # Replay a blob the real Hegel engine emitted. See tools/tracegen: the golden
  # vectors bind each IR function to the engine, this binds a whole shell to it.
  def case_trace(envelope, blob, script, expected)
    # `envelope` records which envelope the engine chose, not what this has to
    # do: both are replayed now that ir/inflate.zir decodes prefix 1.
    _ = envelope
    ops = script.split(",")
    drawn = []
    replay = lambda do |test_case|
      ops.each { |op| drawn << ZizekDrawOps.trace_draw(test_case, op) }
      raise "replay"
    end
    assert_raises(Zizek::Failure) { Zizek.check(replay, reproduce: blob) }
    assert_equal expected, drawn.join(","),
                 "replayed the engine's blob as #{drawn.join(',')}, want #{expected}"
    nil
  end

  def test_shell_cases
    cases = shell_cases
    refute_empty cases, "no shared shell cases were run"
    pinned = 0
    cases.each do |kind, *rest|
      # An optional trailing blob=<base64> pins the reproduce blob the case
      # must emit. It is stripped before dispatch so the handlers keep their
      # positional arguments, and compared against what the handler returns.
      # See conformance/shell/shell_cases.tsv.
      expected_blob = rest.last&.start_with?("blob=") ? rest.pop.delete_prefix("blob=") : nil
      emitted, handled = ZizekShellCases.run(self, kind, rest)
      emitted = send("case_#{kind.downcase}", *rest) unless handled
      next if expected_blob.nil?

      assert_equal expected_blob, emitted,
                   "#{kind} emitted #{emitted.inspect}, want the shared #{expected_blob.inspect}"
      pinned += 1
    end
    assert pinned.positive?, "no shared case pinned its blob"
  end

end

# The coverage assertion family.
class CoverageAssertionTest < Minitest::Test
  def test_sometimes_never_held_fails_the_run
    property = lambda do |test_case|
      value = test_case.integer(0, 10)
      test_case.sometimes("value above range", value > 1000)
    end
    missed = assert_raises(Zizek::FailedCoverage) do
      Zizek.check(property, examples: 20, seed: 5)
    end
    assert_equal "value above range", missed.label
    assert_equal 0, missed.observed
    assert_equal 20, missed.valid
    assert_equal 0, missed.min_percent
  end

  def test_sometimes_held_once_passes
    attempts = []
    property = lambda do |test_case|
      attempts << nil
      test_case.sometimes("first example", attempts.length == 1)
    end
    Zizek.check(property, examples: 20, seed: 5)
  end

  def test_declared_label_never_executed_fails_the_run
    missed = assert_raises(Zizek::FailedCoverage) do
      Zizek.check(
        ->(_test_case) {},
        examples: 10,
        must_cover: [Zizek::Coverage.new("unreached branch")]
      )
    end
    assert_equal "unreached branch", missed.label
    assert_equal 0, missed.observed
    assert_equal 10, missed.valid
  end

  def test_declared_label_observed_at_a_call_site_passes
    property = lambda do |test_case|
      test_case.sometimes("reached", true)
    end
    Zizek.check(property, examples: 10, must_cover: [Zizek::Coverage.new("reached")])
  end

  def test_declared_labels_are_checked_before_observed_ones
    property = lambda do |test_case|
      test_case.sometimes("observed but missed", false)
    end
    missed = assert_raises(Zizek::FailedCoverage) do
      Zizek.check(
        property,
        examples: 5,
        must_cover: [Zizek::Coverage.new("declared and missed")]
      )
    end
    assert_equal "declared and missed", missed.label
  end

  def test_cover_counts_once_per_example_and_enforces_the_rate
    attempts = []
    property = lambda do |test_case|
      attempts << nil
      # Two hits at the same call-site label in one example count once.
      test_case.cover("first example", attempts.length == 1, percent: 100)
      test_case.cover("first example", attempts.length == 1, percent: 100)
    end
    missed = assert_raises(Zizek::FailedCoverage) do
      Zizek.check(property, examples: 4, seed: 5)
    end
    assert_equal 1, missed.observed
    assert_equal 4, missed.valid
    assert_equal 100, missed.min_percent
  end

  def test_rejected_examples_discard_coverage_observations
    attempts = []
    property = lambda do |test_case|
      attempts << nil
      # The condition holds only on attempts an assumption then rejects, so a
      # shell that commits observations from rejected examples passes.
      test_case.sometimes("rejected attempts only", attempts.length.odd?)
      test_case.assume(attempts.length.even?)
    end
    missed = assert_raises(Zizek::FailedCoverage) do
      Zizek.check(property, examples: 10, seed: 5)
    end
    assert_equal 0, missed.observed
  end

  def test_coverage_is_not_checked_when_a_run_finds_a_counterexample
    property = lambda do |test_case|
      test_case.sometimes("never held", false)
      raise "real bug"
    end
    assert_raises(Zizek::Failure) { Zizek.check(property, examples: 10, seed: 5) }
  end

  def test_reproduce_skips_coverage_verdicts
    property = lambda do |test_case|
      test_case.integer(0, 10)
      raise "always fails"
    end
    failure = assert_raises(Zizek::Failure) { Zizek.check(property, examples: 5, seed: 5) }
    assert_raises(Zizek::Failure) do
      Zizek.check(
        property,
        reproduce: failure.blob,
        must_cover: [Zizek::Coverage.new("impossible during replay")]
      )
    end
  end

  def test_required_coverage_percent_is_validated
    assert_raises(ArgumentError) do
      Zizek.check(
        ->(_test_case) {},
        examples: 1,
        must_cover: [Zizek::Coverage.new("rate", percent: 101)]
      )
    end
  end

  def test_always_failure_shrinks_to_the_simplest_violation
    property = lambda do |test_case|
      value = test_case.integer(0, 100)
      test_case.always("value stays small", value < 5)
    end
    failure = assert_raises(Zizek::Failure) do
      Zizek.check(property, examples: 100, seed: 3)
    end
    assert_includes failure.property_cause.message,
                    'always: "value stays small" did not hold'
    replayed = []
    replay = lambda do |test_case|
      replayed << test_case.integer(0, 100)
      test_case.always("value stays small", replayed.last < 5)
    end
    assert_raises(Zizek::Failure) { Zizek.check(replay, reproduce: failure.blob) }
    assert_equal 5, replayed.last
  end

  # Two assertions with disjoint failing ranges. The shrinker must stay on
  # whichever bug generation found: if both call sites collapsed into one
  # origin, a search that found the 90..100 bug would accept 40..60 candidates
  # as progress and report the wrong assertion's boundary.
  def test_two_always_sites_are_distinct_bugs
    property = lambda do |test_case|
      value = test_case.integer(0, 100)
      test_case.always("mid stays out", !value.between?(40, 60))
      test_case.always("large stays out", value < 90)
    end
    failure = assert_raises(Zizek::Failure) do
      Zizek.check(property, examples: 100, seed: 3)
    end
    replayed = []
    replay = lambda do |test_case|
      value = test_case.integer(0, 100)
      replayed << value
      test_case.always("mid stays out", !value.between?(40, 60))
      test_case.always("large stays out", value < 90)
    end
    assert_raises(Zizek::Failure) { Zizek.check(replay, reproduce: failure.blob) }
    cause = failure.property_cause.message
    expected = cause.include?("mid stays out") ? 40 : 90
    assert_equal expected, replayed.last
  end

  def test_always_that_holds_passes_and_covers_its_label
    property = lambda do |test_case|
      test_case.always("invariant", true)
    end
    Zizek.check(property, examples: 10, must_cover: [Zizek::Coverage.new("invariant")])
  end

  def test_required_always_site_that_never_runs_fails_the_run
    property = lambda do |test_case|
      value = test_case.integer(0, 10)
      test_case.always("guarded invariant", true) if value > 1000
    end
    missed = assert_raises(Zizek::FailedCoverage) do
      Zizek.check(
        property,
        examples: 20,
        seed: 5,
        must_cover: [Zizek::Coverage.new("guarded invariant")]
      )
    end
    assert_equal "guarded invariant", missed.label
  end

  def test_unreachable_fails_with_the_simplest_reaching_input
    property = lambda do |test_case|
      value = test_case.integer(0, 100)
      test_case.unreachable("dead branch") if value > 5
    end
    failure = assert_raises(Zizek::Failure) do
      Zizek.check(property, examples: 100, seed: 3)
    end
    assert_includes failure.property_cause.message,
                    'unreachable: "dead branch" was reached'
    replayed = []
    replay = lambda do |test_case|
      replayed << test_case.integer(0, 100)
      test_case.unreachable("dead branch") if replayed.last > 5
    end
    assert_raises(Zizek::Failure) { Zizek.check(replay, reproduce: failure.blob) }
    assert_equal 6, replayed.last
  end

  def test_unreachable_never_reached_passes
    property = lambda do |test_case|
      value = test_case.integer(0, 10)
      test_case.unreachable("dead branch") if value > 1000
    end
    Zizek.check(property, examples: 20, seed: 5)
  end
end

class CloneStreamTest < Minitest::Test
  # --- cloned streams ------------------------------------------------------

  def clone_property(threshold, seen)
    lambda do |test_case|
      outer = test_case.integer(0, 100)
      child = test_case.clone_stream
      inner = child.integer(0, 100)
      tail = test_case.integer(0, 100)
      seen.replace([outer, inner, tail])
      raise "inner too big: #{inner}" if inner >= threshold
    end
  end

  def test_clone_stream_is_framed_and_replays
    seen = []
    failure = assert_raises(Zizek::Failure) do
      Zizek.check(clone_property(40, seen), examples: 200, seed: 7)
    end
    raw = Zizek.const_get(:Core).raw_failure_decode(failure.blob)
    refute_nil raw
    assert Zizek.const_get(:Core).choice_stream_validate(raw)
    # Three top-level entries: the outer draw, the clone, the trailing draw.
    assert_equal 3, Zizek.const_get(:Core).choice_stream_count(raw)
    offset = Zizek.const_get(:Core).choice_offset_at(raw, 1)
    refute_nil offset
    assert_equal 5, raw.getbyte(offset)
    inner = Zizek.const_get(:Core).clone_inner_stream(raw, offset)
    refute_nil inner
    assert_equal 1, Zizek.const_get(:Core).choice_stream_count(inner)

    seen = []
    assert_raises(Zizek::Failure) do
      Zizek.check(clone_property(40, seen), reproduce: failure.blob)
    end
    assert_operator seen[1], :>=, 40
  end

  def test_clone_stream_shrinks_its_own_choices
    # Every seed must reach the same minimum: the clone's draw at exactly the
    # threshold, everything around it at zero. Without a nested pass the flat
    # passes step over the clone as one atomic entry and report whatever value
    # generation found.
    blob = nil
    [1, 2, 3, 7, 11].each do |seed|
      seen = []
      failure = assert_raises(Zizek::Failure) do
        Zizek.check(clone_property(40, seen), examples: 200, seed: seed)
      end
      assert_equal [0, 40, 0], seen, "seed #{seed}"
      blob ||= failure.blob
      assert_equal blob, failure.blob, "seed #{seed}"
    end
  end

  def test_nested_clones_shrink_at_every_depth
    seen = []
    property = lambda do |test_case|
      child = test_case.clone_stream
      outer = child.integer(0, 100)
      grandchild = child.clone_stream
      inner = grandchild.integer(0, 100)
      seen.replace([outer, inner])
      raise "both too big" if outer >= 10 && inner >= 20
    end
    failure = assert_raises(Zizek::Failure) do
      Zizek.check(property, examples: 300, seed: 4)
    end
    assert_equal [10, 20], seen
    seen.clear
    assert_raises(Zizek::Failure) { Zizek.check(property, reproduce: failure.blob) }
    assert_equal [10, 20], seen
  end

  def test_clone_replay_puns_a_non_clone_entry_to_an_empty_child
    stream = Zizek.const_get(:Core).choice_list_header(2) +
             Zizek.const_get(:Core).serialize_integer_choice([3].pack("c")) +
             Zizek.const_get(:Core).serialize_integer_choice([4].pack("c"))
    blob = Zizek.const_get(:Core).raw_failure_encode(stream)
    property = lambda do |test_case|
      test_case.integer(0, 100)
      child = test_case.clone_stream
      child.integer(0, 100)
    end
    assert_raises(Zizek::ReplayOverrun) { Zizek.check(property, reproduce: blob) }
  end

  def test_clones_share_the_family_report
    property = lambda do |test_case|
      child = test_case.clone_stream
      child.note("from the clone")
      child.cost("faults", 2)
      child.integer(0, 10)
      raise "notes did not reach the family" unless test_case.__send__(:notes) == ["from the clone"]
      raise "costs did not reach the family" unless test_case.__send__(:total_cost) == 2
    end
    Zizek.check(property, examples: 5, seed: 1)
  end

  def test_cloning_past_the_nesting_limit_rejects_the_example
    # The wire format refuses to validate a stream nested deeper than 100, so
    # the shell refuses to build one. Upstream concludes the family invalid
    # there, which is a rejection rather than a property failure.
    property = lambda do |test_case|
      at = test_case
      (Zizek::TestCase.const_get(:MAX_CLONE_DEPTH) + 1).times { at = at.clone_stream }
      raise "reached past the nesting limit"
    end
    assert_raises(Zizek::TooManyRejections) do
      Zizek.check(property, examples: 5, seed: 1, suppress_filter_too_much: true)
    end
  end
end

# Settings, profiles, and the derandomized seed.
class SettingsTest < Minitest::Test
  def teardown
    Zizek.load_profile(:default)
  end

  def test_unknown_setting_raises_at_construction
    error = assert_raises(ArgumentError) { Zizek::Settings.new(exampels: 5) }
    assert_includes error.message, "unknown setting: :exampels"
  end

  def test_settings_are_frozen_values
    settings = Zizek::Settings.new(examples: 5)
    assert_predicate settings, :frozen?
    assert_equal 5, settings.examples
    assert_equal 50, settings.with(examples: 50).examples
    assert_equal 5, settings.examples, "with must not mutate the receiver"
    assert_same settings, settings.with, "an empty with should not allocate"
  end

  def test_settings_round_trip_through_to_h
    settings = Zizek::Settings.new(examples: 7, seed: 3, derandomize: true)
    assert_equal settings, Zizek::Settings.new(**settings.to_h)
  end

  def test_must_cover_accepts_labels_and_coverage_entries
    settings = Zizek::Settings.new(must_cover: ["reached", Zizek::Coverage.new("rate", percent: 5)])
    assert_equal [Zizek::Coverage.new("reached"), Zizek::Coverage.new("rate", percent: 5)],
                 settings.must_cover
  end

  def test_validation_rejects_impossible_configuration
    assert_raises(ArgumentError) { Zizek::Settings.new(examples: 0) }
    assert_raises(ArgumentError) { Zizek::Settings.new(max_shrinks: -1) }
    assert_raises(ArgumentError) { Zizek::Settings.new(must_cover: [Zizek::Coverage.new("x", percent: 101)]) }
  end

  def test_profiles_supply_defaults_that_call_sites_override
    Zizek.register_profile(:tiny, examples: 3)
    Zizek.load_profile(:tiny)
    assert_equal 3, Zizek.current_settings.examples

    seen = 0
    Zizek.check(->(_test_case) { seen += 1 })
    assert_equal 3, seen, "the active profile should supply examples"

    seen = 0
    Zizek.check(->(_test_case) { seen += 1 }, examples: 9)
    assert_equal 9, seen, "a keyword should override the active profile"
  end

  def test_with_profile_restores_the_previous_profile_on_raise
    Zizek.register_profile(:scoped, examples: 2)
    assert_raises(RuntimeError) do
      Zizek.with_profile(:scoped) do
        assert_equal :scoped, Zizek.current_profile
        raise "boom"
      end
    end
    assert_equal :default, Zizek.current_profile
  end

  def test_unknown_profile_names_the_registered_ones
    error = assert_raises(KeyError) { Zizek.profile(:nope) }
    assert_includes error.message, "unknown profile :nope"
  end

  def test_derandomize_derives_a_stable_seed_from_the_property
    property = lambda { |test_case| test_case.integer(0, 10) }
    settings = Zizek::Settings.new(derandomize: true)
    assert_equal settings.__send__(:effective_seed, property), settings.__send__(:effective_seed, property)
    other = lambda { |test_case| test_case.integer(0, 10) }
    refute_equal settings.__send__(:effective_seed, property), settings.__send__(:effective_seed, other),
                 "two properties in different places should not share a seed"
  end

  def test_an_explicit_seed_beats_derandomize
    property = lambda { |test_case| test_case.integer(0, 10) }
    assert_equal 42, Zizek::Settings.new(derandomize: true, seed: 42).__send__(:effective_seed, property)
  end

  def test_a_settings_object_can_be_passed_directly
    seen = 0
    Zizek.check(->(_test_case) { seen += 1 }, settings: Zizek::Settings.new(examples: 4))
    assert_equal 4, seen
  end
end

# The falsifying-example report, and check versus run.
class ReportingTest < Minitest::Test
  def failing_property
    lambda do |test_case|
      total = test_case.draw(Zizek::Generators.integers(0..1_000), name: :total)
      people = test_case.draw(Zizek::Generators.integers(1..50), name: :people)
      test_case.cost("split")
      raise "uneven" unless (total % people).zero?
    end
  end

  def test_named_draws_are_reported_in_the_failure
    failure = assert_raises(Zizek::Failure) { Zizek.check(failing_property, examples: 300, seed: 7) }
    assert_equal [[:total, 1], [:people, 2]], failure.values
    assert_includes failure.message, "Falsifying example: (total=1, people=2)"
    assert_includes failure.message, "RuntimeError: uneven"
    assert_includes failure.message, "cost: split=1"
    assert_includes failure.message, "seed: 7"
  end

  def test_naming_a_draw_does_not_change_the_blob
    anonymous = lambda do |test_case|
      value = test_case.draw(Zizek::Generators.integers(0..100))
      raise "too large" unless value < 5
    end
    named = lambda do |test_case|
      value = test_case.draw(Zizek::Generators.integers(0..100), name: :value)
      raise "too large" unless value < 5
    end
    bare = assert_raises(Zizek::Failure) { Zizek.check(anonymous, examples: 200, seed: 1) }
    labelled = assert_raises(Zizek::Failure) { Zizek.check(named, examples: 200, seed: 1) }
    assert_equal bare.blob, labelled.blob
    assert_empty bare.values
    assert_equal [[:value, 5]], labelled.values
  end

  def test_run_reports_a_counterexample_instead_of_raising
    result = Zizek.run(failing_property, examples: 300, seed: 7)
    refute_predicate result, :ok?
    assert_predicate result, :failure?
    assert_equal :failure, result.outcome
    assert_equal [[:total, 1], [:people, 2]], result.values
    assert_equal 7, result.seed
    refute_nil result.blob
    assert_raises(Zizek::Failure) { result.raise! }
  end

  def test_run_reports_a_clean_pass
    result = Zizek.run(->(test_case) { test_case.integer(0, 3) }, examples: 20, seed: 1)
    assert_predicate result, :ok?
    refute_predicate result, :failure?
    assert_equal 20, result.examples_run
    assert_equal 1, result.seed
    assert_nil result.raise!
  end

  def test_run_reports_a_missed_coverage_requirement_as_an_outcome
    result = Zizek.run(->(test_case) { test_case.integer(0, 3) },
                       examples: 5, seed: 1, must_cover: ["never reached"])
    refute_predicate result, :ok?
    refute_predicate result, :failure?
    assert_equal :coverage, result.outcome
    assert_kind_of Zizek::FailedCoverage, result.error
  end

  def test_run_still_raises_for_an_invalid_blob
    assert_raises(Zizek::InvalidReplay) do
      Zizek.run(->(test_case) { test_case.integer(0, 3) }, reproduce: "not a blob")
    end
  end

  def test_the_reported_blob_replays
    failure = assert_raises(Zizek::Failure) { Zizek.check(failing_property, examples: 300, seed: 7) }
    replayed = assert_raises(Zizek::Failure) { Zizek.check(failing_property, reproduce: failure.blob) }
    assert_equal failure.blob, replayed.blob
    assert_equal failure.values, replayed.values
  end
end

# The keyword factories, ranges, and combinators.
class GeneratorSurfaceTest < Minitest::Test
  G = Zizek::Generators

  def draws(generator, count: 25)
    (0...count).map { |seed| generator.example(seed: seed) }
  end

  def test_keyword_integers_match_the_fluent_builder
    assert_equal draws(G.integers.min_value(0).max_value(100)),
                 draws(G.integers(min: 0, max: 100))
    assert_equal draws(G.integers.min_value(-100).max_value(100).shrink_towards(10)),
                 draws(G.integers(min: -100, max: 100, shrink_towards: 10))
  end

  # Compared as bit patterns: a NaN is never == to itself, so two identical
  # float streams would otherwise look different.
  def float_bits(generator, count: 25)
    draws(generator, count: count).map { |value| [value].pack("E") }
  end

  def test_keyword_floats_match_the_fluent_builder
    assert_equal float_bits(G.floats.min_value(0.0).max_value(1.0)),
                 float_bits(G.floats(min: 0.0, max: 1.0))
    assert_equal float_bits(G.floats.allow_nan(true).allow_infinity(true)),
                 float_bits(G.floats(allow_nan: true, allow_infinity: true))
  end

  def test_an_inclusive_range_is_the_same_as_min_and_max
    assert_equal draws(G.integers(min: 0, max: 100)), draws(G.integers(0..100))
    assert_equal float_bits(G.floats(min: 0.0, max: 1.0)), float_bits(G.floats(0.0..1.0))
  end

  def test_an_exclusive_integer_range_drops_its_endpoint
    assert_equal draws(G.integers(min: 0, max: 99)), draws(G.integers(0...100))
  end

  def test_a_half_open_range_leaves_the_other_bound_at_its_default
    assert_operator draws(G.integers(0..), count: 40).min, :>=, 0
    assert_operator draws(G.integers(..0), count: 40).max, :<=, 0
  end

  def test_a_range_and_explicit_bounds_are_mutually_exclusive
    error = assert_raises(ArgumentError) { G.integers(0..10, min: 5) }
    assert_includes error.message, "either a range or min:/max:"
  end

  def test_floats_refuse_an_exclusive_range
    error = assert_raises(ArgumentError) { G.floats(0.0...1.0) }
    assert_includes error.message, "excludes its end"
  end

  def test_pipe_builds_a_flat_one_of
    union = G.integers(max: 0) | G.text(max: 2) | G.booleans
    assert_instance_of G.const_get(:OneOfGenerator), union
    assert_equal 3, union.__send__(:choices).length, "a | chain should flatten, not nest"
    assert_equal draws(G.one_of(G.integers(max: 0), G.text(max: 2), G.booleans)), draws(union)
  end

  def test_one_of_with_a_single_choice_is_that_choice
    generator = G.integers(0..5)
    assert_same generator, G.one_of(generator)
  end

  def test_example_produces_a_value_without_a_property
    assert_equal G.integers(0..100).example(seed: 3), G.integers(0..100).example(seed: 3)
    assert_includes 0..100, G.integers(0..100).example(seed: 3)
  end

  def test_example_gives_up_on_an_unsatisfiable_filter
    assert_raises(Zizek::Unsatisfiable) do
      G.integers(0..100).filter { |value| value > 1_000 }.example(seed: 1)
    end
  end

  def test_builds_assembles_an_object_from_drawn_parts
    point = Struct.new(:x, :y)
    drawn = G.builds(point, G.integers(0..9), G.integers(0..9)).example(seed: 3)
    assert_instance_of point, drawn
    assert_includes 0..9, drawn.x

    keyword = G.builds(point, x: G.integers(0..9), y: G.integers(0..9)).example(seed: 3)
    assert_includes 0..9, keyword.y
  end

  def test_builds_passes_plain_values_through
    assert_equal 7..7, G.builds(->(low, high) { low..high }, G.integers(7..7), 7).example(seed: 1)
  end

  def test_composite_is_handed_the_test_case
    ordered = G.composite do |test_case|
      low = test_case.draw(G.integers(0..10))
      [low, test_case.draw(G.integers(min: low, max: 20))]
    end
    low, high = ordered.example(seed: 5)
    assert_operator low, :<=, high
  end
end

# The class-shaped state machine.
class MachineTest < Minitest::Test
  class CounterMachine < Zizek::Stateful::Machine
    def initialize(start: 0)
      @count = start
      @seen = []
    end

    attr_reader :count, :seen

    rule(:increment) do |test_case|
      @count += test_case.draw(Zizek::Generators.integers(1..3))
    end

    rule(:reset) do |test_case|
      test_case.assume(@count.positive?)
      @count = 0
    end

    invariant(:never_negative) do
      raise "count went negative" if @count.negative?
    end
  end

  class ExtendedMachine < CounterMachine
    rule(:remember) { |_test_case| @seen << @count }
  end

  def test_declared_rules_and_invariants_become_the_machine_protocol
    machine = CounterMachine.new
    assert_equal %w[increment reset], machine.rules.map(&:name)
    assert_equal %w[never_negative], machine.invariants.map(&:name)
  end

  def test_rule_bodies_run_against_the_machine
    Zizek.check(CounterMachine.property, examples: 20, seed: 1)
  end

  def test_property_accepts_constructor_arguments
    Zizek.check(CounterMachine.property(start: 5), examples: 20, seed: 1)
  end

  def test_a_subclass_inherits_its_parents_rules
    assert_equal %w[increment reset remember], ExtendedMachine.new.rules.map(&:name)
    assert_equal %w[increment reset], CounterMachine.new.rules.map(&:name),
                 "a subclass must not add rules to its parent"
  end

  def test_a_rule_without_a_block_is_rejected
    assert_raises(ArgumentError) { Class.new(Zizek::Stateful::Machine) { rule(:nope) } }
  end

  # The DSL is sugar over the Rule array, so it must produce the identical
  # choice stream — and therefore the identical portable blob.
  class QueueMachine < Zizek::Stateful::Machine
    def initialize
      @machine = QueueExample::QueueTest.new
    end

    rule(:push) { |test_case| @machine.push(test_case) }
    rule(:pop) { |test_case| @machine.pop(test_case) }
    invariant(:sizes_agree) { |test_case| @machine.sizes_agree(test_case) }
  end

  def test_the_dsl_shrinks_to_the_same_blob_as_the_manual_rule_array
    failure = assert_raises(Zizek::Failure) do
      Zizek.check(QueueMachine.property, examples: 2_000, seed: 3)
    end
    assert_equal QueueExample::PORTABLE_QUEUE_FAILURE, failure.blob
  end
end

# The example database: storage, the reuse phase, and what it collects.
#
# The shared table in DatabaseConformanceTest is the cross-language gate; these
# are the Ruby surface's own — coercions, the derived key, and the best-effort
# promise that a database which cannot be written never fails a run.
class DatabaseTest < Minitest::Test
  def failing(lo = 0, hi = 100, threshold = 5)
    lambda do |test_case|
      raise "value reached #{threshold}" unless test_case.integer(lo, hi) < threshold
    end
  end

  def harmless(lo = 0, hi = 100)
    ->(test_case) { test_case.integer(lo, hi) }
  end

  def test_database_is_off_until_asked_for
    # A library call that wrote into the working directory unasked would be a
    # surprise, so the default stores nothing and reads nothing.
    assert_nil Zizek::Settings.new.database
    assert_nil Zizek::Database.__send__(:resolve, Zizek::Settings.new.database)
  end

  def test_resolve_accepts_the_shorthands
    assert_nil Zizek::Database.__send__(:resolve, nil)
    assert_nil Zizek::Database.__send__(:resolve, false)
    assert_equal Zizek::Database::Directory.new(Zizek::Database::DEFAULT_PATH),
                 Zizek::Database.__send__(:resolve, true)
    assert_equal Zizek::Database::Directory.new("/tmp/zizek"),
                 Zizek::Database.__send__(:resolve, "/tmp/zizek")
    assert_instance_of Zizek::Database::Memory, Zizek::Database.__send__(:resolve, ":memory:")
    existing = Zizek::Database::Memory.new
    assert_same existing, Zizek::Database.__send__(:resolve, existing)
  end

  def test_resolve_rejects_an_object_that_is_not_a_database
    error = assert_raises(ArgumentError) { Zizek::Settings.new(database: Object.new) }
    assert_includes error.message, "fetch"
  end

  def test_digests_are_the_compiled_key_hash
    # The whole cross-language claim rests on this being the same hash a keyed
    # draw uses, not a host one.
    assert_equal format("%016x", Zizek.key_hash("split_is_exact")),
                 Zizek::Database.__send__(:digest, "split_is_exact")
  end

  def test_a_stored_counterexample_replaces_a_larger_one
    # An entry stored by a weaker shrinker, or by an older build, is replayed,
    # shrunk again, and replaced by what it shrank to.
    database = Zizek::Database::Memory.new
    larger = ["01000000000a0100000032"].pack("H*")
    database.save("case", larger)
    failure = assert_raises(Zizek::Failure) do
      Zizek.check(failing, examples: 200, seed: 1, database: database, database_key: "case")
    end
    shrunk = Zizek.const_get(:Core).raw_failure_decode(failure.blob.b)
    assert_equal [shrunk], database.fetch("case")
    refute_equal larger, shrunk
  end

  def test_reproduce_leaves_the_database_alone
    # Replaying a blob by hand is a manual operation; one that quietly rewrote
    # a shared directory would be a surprise.
    database = Zizek::Database::Memory.new
    found = assert_raises(Zizek::Failure) do
      Zizek.check(failing, examples: 200, seed: 1, database: ":memory:")
    end
    assert_raises(Zizek::Failure) do
      Zizek.check(failing, reproduce: found.blob, database: database, database_key: "case")
    end
    assert_empty database.fetch("case")
  end

  def test_a_database_that_cannot_be_written_does_not_fail_the_run
    Dir.mktmpdir do |root|
      blocked = File.join(root, "not-a-directory")
      File.binwrite(blocked, "")
      database = Zizek::Database::Directory.new(blocked)
      assert_raises(Zizek::Failure) do
        Zizek.check(failing, examples: 200, seed: 1, database: database, database_key: "case")
      end
      assert_empty database.fetch("case")
    end
  end

  def test_a_key_directory_ignores_what_it_did_not_write
    Dir.mktmpdir do |root|
      database = Zizek::Database::Directory.new(root)
      database.save("case", "\x00\x00\x00\x00".b)
      key_dir = File.join(root, Zizek::Database.__send__(:digest, "case"))
      File.write(File.join(key_dir, "README"), "checked in on purpose")
      File.write(File.join(key_dir, ".gitignore"), "")
      assert_equal ["\x00\x00\x00\x00".b], database.fetch("case")
    end
  end

  def test_saving_the_same_stream_twice_stores_it_once
    Dir.mktmpdir do |root|
      database = Zizek::Database::Directory.new(root)
      database.save("case", "\x00\x00\x00\x00".b)
      database.save("case", "\x00\x00\x00\x00".b)
      assert_equal ["\x00\x00\x00\x00".b], database.fetch("case")
    end
  end

  def test_an_emptied_key_leaves_no_directory_behind
    Dir.mktmpdir do |root|
      database = Zizek::Database::Directory.new(root)
      database.save("case", "\x00\x00\x00\x00".b)
      database.delete("case", "\x00\x00\x00\x00".b)
      refute File.exist?(File.join(root, Zizek::Database.__send__(:digest, "case")))
    end
  end

  def test_deleting_one_of_several_keeps_the_directory_labelled
    # The .name file goes with the last entry, not the first: a directory that
    # still holds counterexamples must keep the label that says whose they are.
    Dir.mktmpdir do |root|
      database = Zizek::Database::Directory.new(root)
      database.save("case", "\x00\x00\x00\x00".b)
      database.save("case", "\x01\x00\x00\x00".b)
      database.delete("case", "\x00\x00\x00\x00".b)
      key_dir = File.join(root, Zizek::Database.__send__(:digest, "case"))
      assert_equal "case", File.binread(File.join(key_dir, ".name"))
      assert_equal ["\x01\x00\x00\x00".b], database.fetch("case")
    end
  end

  def test_deleting_what_is_not_there_is_quiet
    database = Zizek::Database::Memory.new
    database.delete("case", "\x00\x00\x00\x00".b)
    assert_empty database.fetch("case")
  end

  def test_a_run_without_a_key_names_itself_after_where_the_property_was_written
    database = Zizek::Database::Memory.new
    property = failing
    assert_raises(Zizek::Failure) do
      Zizek.check(property, examples: 200, seed: 1, database: database)
    end
    assert_equal 1, database.fetch(Zizek::Settings.__send__(:property_identity, property)).length
  end
end

# The cross-language gate for the example database.
#
# See conformance/database/database_cases.tsv, which every database-enabled shell runs: a
# digest or a reuse rule that drifts in one language fails here rather than in
# a shared directory three months later.
class DatabaseConformanceTest < Minitest::Test
  CASES = File.expand_path("../../../conformance/database/database_cases.tsv", __dir__)

  def database_cases
    unless File.exist?(CASES)
      raise "#{CASES} is missing: the shared conformance tables live in the " \
            "Zizek source tree and are not shipped with this package"
    end

    # Read as UTF-8 explicitly: one DB_DIGEST row carries a non-ASCII name on
    # purpose, and the default external encoding is the machine's, not the
    # table's.
    File.readlines(CASES, chomp: true, encoding: "UTF-8")
        .reject { |line| line.empty? || line.start_with?("#") }
        .map { |line| line.split("\t") }
  end

  def test_database_cases
    cases = database_cases
    refute_empty cases, "no shared database cases were run"
    pinned = 0
    cases.each do |kind, *rest|
      expected_blob = rest.last&.start_with?("blob=") ? rest.pop.delete_prefix("blob=") : nil
      emitted, handled = DatabaseCasesGen.run(self, kind, rest)
      assert handled, "unknown database case #{kind.inspect}"
      next if expected_blob.nil?

      assert_equal expected_blob, emitted,
                   "#{kind} emitted #{emitted.inspect}, want the shared #{expected_blob.inspect}"
      pinned += 1
    end
    assert pinned.positive?, "no shared database case pinned its blob"
  end
end
