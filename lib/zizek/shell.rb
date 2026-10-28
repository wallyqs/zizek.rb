# frozen_string_literal: true

require "set"

require_relative "gen"

module Zizek
  class InvalidReplay < ArgumentError; end
  class ReplayOverrun < StandardError; end
  class ChoiceOverrun < StandardError; end
  class AssumptionRejected < StandardError; end

  # No value could be produced. Raised by Generators::Combinators#example when
  # a filter rejects every attempt; a property reports this as a health check
  # instead, because inside a run a rejection is data about the search.
  class Unsatisfiable < StandardError; end

  class FailedHealthCheck < StandardError
    attr_reader :check

    def initialize(check, message)
      @check = check
      super(message)
    end
  end

  # A coverage requirement the completed run missed.
  #
  # There is no counterexample and so no blob or shrinking: the failure is the
  # absence of an example, not an example. The counters are a pure function of
  # the run's choice streams, so rerunning with the same seed reproduces the
  # identical verdict.
  class FailedCoverage < StandardError
    # min_percent is the strongest rate required for the label across its call
    # sites and require entries; zero means "at least once".
    attr_reader :label, :observed, :valid, :min_percent

    def initialize(label, observed, valid, min_percent)
      @label = label
      @observed = observed
      @valid = valid
      @min_percent = min_percent
      message =
        if min_percent.zero?
          "coverage: \"#{label}\" never held in #{valid} valid examples"
        else
          "coverage: \"#{label}\" held in #{observed} of #{valid} valid " \
            "examples, below the required #{format('%g', min_percent)}%"
        end
      super(message)
    end
  end

  class TooManyRejections < StandardError
    attr_reader :rejections, :limit

    def initialize(rejections, limit)
      @rejections = rejections
      @limit = limit
      super("too many rejected examples: got #{rejections} rejections (limit #{limit})")
    end
  end

  class Failure < StandardError
    attr_reader :blob, :property_cause, :examples_run, :rejections, :notes, :values, :seed,
                :puns, :key_misses, :costs
    alias cause property_cause

    # Keyword-only because there are ten of these and a positional call site
    # said nothing about which zero meant what.
    def initialize(blob:, property_cause:, examples_run:, rejections: 0, notes: [], values: [],
                   seed: nil, puns: 0, key_misses: 0, costs: {})
      @blob = blob
      @property_cause = property_cause
      @examples_run = examples_run
      @rejections = rejections
      @notes = notes.freeze
      # The named draws this example made, in draw order. See TestCase#draw:
      # naming is for the report only and records no choice, so a blob replays
      # identically whether or not its draws were named.
      @values = values.freeze
      # The seed this search ran under. The blob is the portable artifact; the
      # seed only repeats this search, in this language and version.
      @seed = seed
      # Replayed draws that could not use their recorded value. See
      # ir/replay.zir: a pun is legal but silent, so it is counted rather than
      # raised.
      @puns = puns
      # Keyed draws whose name the blob did not carry.
      @key_misses = key_misses
      # What the reported example spent.
      @costs = costs.freeze
      super(render)
    end

    private

    def render
      lines = []
      unless values.empty?
        arguments = values.map { |name, value| "#{name}=#{value.inspect}" }.join(", ")
        lines << "Falsifying example: (#{arguments})"
      end
      detail = property_cause.message.to_s
      lines << (detail.empty? ? property_cause.class.name : "#{property_cause.class}: #{detail}")
      unless costs.empty?
        lines << "cost: #{costs.map { |label, amount| "#{label}=#{amount}" }.join(", ")}"
      end
      lines << "reproduce with: Zizek.check(property, reproduce: #{blob.inspect})"
      unless key_misses.zero?
        noun = key_misses == 1 ? "draw was" : "draws were"
        lines << "warning: #{key_misses} keyed #{noun} not in this blob and " \
                 "used the simplest value instead"
      end
      unless puns.zero?
        # The values above are not the ones the blob recorded. Say so: a
        # punned replay is a different run wearing the same blob.
        noun = puns == 1 ? "choice" : "choices"
        lines << "warning: #{puns} replayed #{noun} did not fit this property " \
                 "and fell back to a default; the example above is not the one " \
                 "the blob recorded"
      end
      lines << "seed: #{seed}" unless seed.nil?
      rendered = lines.join("\n")
      rendered += "\n\nTrace:\n- #{notes.join("\n- ")}" unless notes.empty?
      rendered
    end
  end

  # A failure that did not fail the same way when its own choices were
  # replayed: the property depends on something other than what it drew. There
  # is no shrunk example to trust, so this carries the failure as first found
  # and the blob of the stream that produced it. Unlike a Failure's, that blob
  # need not fail when reproduced.
  class Flaky < StandardError
    attr_reader :blob, :property_cause, :examples_run, :rejections, :seed
    alias cause property_cause

    def initialize(blob:, property_cause:, examples_run:, rejections: 0, seed: nil)
      @blob = blob
      @property_cause = property_cause
      @examples_run = examples_run
      @rejections = rejections
      @seed = seed
      super(render)
    end

    private

    def render
      detail = property_cause.message.to_s
      reason = detail.empty? ? property_cause.class.name : "#{property_cause.class}: #{detail}"
      lines = [
        "flaky test: the property failed, then did not fail the same way when " \
        "that example was replayed",
        "original failure: #{reason}",
        "reproduce with: Zizek.check(property, reproduce: #{blob.inspect})"
      ]
      lines << "seed: #{seed}" unless seed.nil?
      lines.join("\n")
    end
  end

  # `encoded` stays the inner entry whether or not the draw is named, so
  # indexing, shrinking, and replay resolution never have to know about keys.
  # `child` is the stream a clone draw carries; nil for every other kind. Its
  # entry is built at serialization time rather than at record time, because
  # the child keeps drawing after the clone is recorded.
  Draw = Struct.new(:kind, :encoded, :value, :params, :forced, :key, :child)

  module Shell
    # A string as the u32-LE codepoints the choice stream records, and back.
    def self.pack_codepoints(value)
      value.codepoints.pack("V*")
    end

    def self.unpack_codepoints(packed)
      packed.unpack("V*").pack("U*")
    end

    # The stream entry for a draw: its value, wrapped if it has a name.
    def self.entry(draw)
      encoded = draw.encoded
      if draw.kind == :clone
        children = draw.child.nil? ? [] : draw.child.__send__(:draws)
        encoded = Core.serialize_clone_header(children.length) +
                  children.map { |child| entry(child) }.join
      end
      return encoded if draw.key.nil?

      Core.serialize_keyed_choice(draw.key, encoded)
    end

    # Give a clone a stream of its own, drawn from its parent's, so two streams
    # never hand back the same values. A parent without an RNG (a bare replay,
    # or the all-simplest probe) has none to give.
    def self.spawn_rng(rng)
      rng.nil? ? nil : Random.new(rng.rand(1 << 62))
    end

    # Count a draw list the way Hegel's flattened length does: a clone
    # contributes itself plus everything inside it.
    def self.flat_draw_count(draws)
      draws.sum { |draw| draw.child.nil? ? 1 : 1 + flat_draw_count(draw.child.__send__(:draws)) }
    end
  end

  # Hash a draw's name into the 64-bit key a stream records.
  #
  # Components may be strings or integers; the encoding is compiled
  # (ir/keys.zir) so the same name hashes identically in every language.
  def self.key_encode(components)
    encoded = +""
    components.each do |component|
      case component
      when Integer
        encoded = Core.key_append_int(encoded, Shell.signed_bytes(component))
      when String, Symbol
        encoded = Core.key_append_text(encoded, component.to_s.b)
      else
        raise ArgumentError, "key components must be String, Symbol, or Integer"
      end
    end
    encoded
  end

  # Use this for a decision the property makes at most once per example. For a
  # decision it makes repeatedly, see TestCase#next_key.
  def self.key_hash(*components)
    Core.key_hash(key_encode(components))
  end

  # The default `text` alphabet: every Unicode scalar value, as Hypothesis
  # uses. Generation is biased towards the simple end of the shrink order, so
  # most drawn characters are still ASCII (see ir/generation.zir).
  UNICODE = Core.alphabet_range(0, 0x10FFFF)

  # The alphabet holding exactly these characters.
  #
  # Alphabets are interval sets, canonical by construction: the order the
  # characters are written in and any repeats among them do not change the
  # result, so `alphabet("cab")` and `alphabet("abc")` are the same alphabet
  # and index their members identically.
  def self.alphabet(characters)
    encoded = +""
    characters.each_codepoint do |codepoint|
      unless Core.alphabet_codepoint_allowed(codepoint)
        raise ArgumentError, "U+#{codepoint.to_s(16).upcase} cannot be an alphabet member"
      end

      encoded = Core.alphabet_insert(encoded, codepoint)
    end
    encoded
  end

  # The alphabet holding every scalar value in a codepoint range. Surrogates
  # are not scalar values and are dropped from the range rather than rejected,
  # so `alphabet_range(0, 0x10FFFF)` is the whole of Unicode.
  def self.alphabet_range(min_codepoint, max_codepoint)
    Core.alphabet_range(min_codepoint, max_codepoint)
  end

  class ChoiceSpan
    attr_accessor :start, :finish, :label, :depth, :parent, :discarded

    def initialize(start:, finish:, label:, depth:, parent:, discarded: false)
      @start = start
      @finish = finish
      @label = label
      @depth = depth
      @parent = parent
      @discarded = discarded
    end
  end

  class TestCase
    attr_reader :draws, :spans, :notes, :drawn

    # How deeply clones may nest. This is Hegel's MAX_CLONE_DEPTH and the wire
    # format's own limit (ir/wire.zir @choice_entry_end): a stream nested
    # deeper than this cannot be validated, so refusing to build one keeps the
    # shell from emitting a blob nothing can read.
    MAX_CLONE_DEPTH = 100

    def initialize(rng: nil, replay: nil, simplest: false, parent: nil)
      # The stream this one was cloned from; nil for the case the property was
      # handed. Everything a run reports — notes, costs, coverage, puns, the
      # choice budget — belongs to the family rather than to one stream, so
      # those route through #root.
      @parent = parent
      # Every draw in the family, including those inside clones. Kept on the
      # root so the choice budget stays O(1) per draw.
      @flat_draws = 0
      @integer_swarm = nil
      @float_swarm = nil
      @rng = rng
      @replay = replay
      @simplest = simplest
      @position = 4
      @remaining = replay.nil? ? 0 : Core.choice_stream_count(replay)
      @draws = []
      @spans = []
      @span_stack = []
      @notes = []
      # Named draws, in draw order, for the falsifying-example report. Local to
      # this stream rather than the family: a clone reports its own.
      @drawn = []
      @generation_depth = 0
      @generation_us = 0
      # Replayed draws that could not use their recorded value; see
      # ir/replay.zir.
      @puns = 0
      # Identifiers handed out by #fresh_id, family-wide so an identifier is
      # unique across every stream of the case. Only ever grows: that is what
      # keeps the recorded windows monotone within a run, so consuming a value
      # cannot destabilize the identifiers recorded after it.
      @fresh_ids = Set.new
      # Keyed draws whose name the stream did not carry. Like a pun this is a
      # silent substitution — the draw falls back to its simplest value — so it
      # is counted rather than raised.
      @key_misses = 0
      @keyed = nil
      # Per-name ordinals for next_key. Execution-local by construction: a
      # counter that outlives one example produces different keys on the replay
      # than on the run that recorded it, and every draw misses.
      @key_counts = {}
      # What this example spent, per label. The shrinker minimizes the total
      # ahead of the choice stream.
      @costs = {}
      # Targeting observations for this example, per label. The run keeps the
      # best-scoring example per label and hill-climbs it on a schedule.
      @targets = {}
      # Coverage observations buffered for this example. Zizek.check commits
      # them into its run-level counters only when the example turns out
      # valid, so a rejected or overrun example contributes nothing — the
      # same convention discarded draws follow.
      @coverage_order = []
      @coverage_held = {}
      @coverage_permille = {}
    end

    attr_reader :coverage_order, :coverage_held, :coverage_permille

    attr_reader :costs

    attr_reader :targets

    # The case the property was handed: the family every clone belongs to.
    def root
      case_at = self
      case_at = case_at.parent until case_at.parent.nil?
      case_at
    end

    # How many clones deep this stream sits.
    def depth
      levels = 0
      case_at = self
      until case_at.parent.nil?
        levels += 1
        case_at = case_at.parent
      end
      levels
    end

    # A child test case that draws from a stream of its own.
    #
    # The clone occupies one choice position in this stream and gets its own
    # prefix, RNG, and span structure, so its draws neither shift nor are
    # shifted by the parent's — which is what makes it the seam a concurrent
    # runner would use. Everything the run reports is shared: notes, costs,
    # coverage, and the choice budget all belong to the family.
    #
    # This is Hegel's hegel_test_case_clone without threads. The child is drawn
    # from sequentially, but the wire framing (`[5][u32 child count][children]`)
    # and the replay rules are the engine's, so a blob carrying a clone crosses
    # between the two.
    #
    # On replay a clone value at this position hands the child its recorded
    # stream. Any other value puns to an empty child, which overruns on its
    # first draw in a bare replay and extends randomly under a probe.
    def clone_stream
      check_choice_budget
      # Upstream concludes the family invalid past the limit rather than
      # failing the property, so this is a rejection: a false assume's path.
      raise AssumptionRejected if depth + 1 > MAX_CLONE_DEPTH

      position, use_simplest = resolve(:clone, nil)
      child = TestCase.new(parent: self)
      if use_simplest
        child.replay_simplest!
      elsif @replay.nil?
        child.replay_random!(Shell.spawn_rng(@rng))
      else
        inner = Core.clone_inner_stream(@replay, position)
        if inner.nil?
          # A non-clone entry where a clone belongs: pun to an empty child.
          root.count_pun!
          inner = Core.choice_list_header(0)
        end
        child.replay_stream!(inner, Shell.spawn_rng(@rng))
      end
      record(Draw.new(:clone, "".b, nil, [], false, nil, child))
      child
    end

    # Append a draw and count it against the family's choice budget.
    def record(draw)
      draws << draw
      root.count_draw!
      nil
    end

    protected

    attr_reader :parent

    # Every identifier the family has ever drawn. Reached through #root:
    # uniqueness is family-wide rather than per stream.
    attr_reader :fresh_ids

    def count_draw!
      @flat_draws += 1
    end

    def count_pun!
      @puns += 1
    end

    def count_key_miss!
      @key_misses += 1
    end

    def flat_draws
      @flat_draws
    end

    def replay_simplest!
      @simplest = true
    end

    def replay_random!(rng)
      @rng = rng
    end

    def replay_stream!(stream, rng)
      @replay = stream
      @remaining = Core.choice_stream_count(stream)
      @rng = rng
    end

    public

    # Record that this example spent something scarce.
    #
    # The shrinker orders candidates by total cost first and by the choice
    # stream second, so a candidate injecting one fewer fault wins even when its
    # stream is longer. A property that never calls this is ordered as before.
    def cost(label, amount = 1)
      raise ArgumentError, "cost amount must be >= 0" if amount.negative?

      costs = root.__send__(:costs)
      costs[label] = costs.fetch(label, 0) + amount
      nil
    end

    def total_cost
      root.__send__(:costs).values.sum
    end

    # Record a targeting observation: generation is steered towards examples
    # that maximize the score. The run keeps, per label, the best-scoring
    # valid example, and hill-climbs those examples on a schedule between
    # ordinary generation. The score must be finite, and each label may be
    # observed at most once per example — a property targeting several
    # quantities names them apart.
    def target(score, label: "")
      score = Float(score)
      unless score.finite?
        raise ArgumentError, "target(#{score}, label: #{label.inspect}) requires a finite score"
      end

      targets = root.__send__(:targets)
      if targets.key?(label)
        raise ArgumentError,
              "target(#{score}, label: #{label.inspect}) would overwrite an earlier " \
              "observation; each label can be observed at most once per example"
      end
      targets[label] = score
      nil
    end

    # The key naming the next draw in a sequence.
    #
    # Appends an ordinal counted *within this name*, so `next_key("read", conn)`
    # numbers that connection's reads independently of every other sequence. An
    # insertion then shifts only its own sequence.
    def next_key(*components)
      scope = Zizek.__send__(:key_encode, components)
      ordinal = @key_counts.fetch(scope, 0)
      @key_counts[scope] = ordinal + 1
      Core.key_hash(Core.key_append_int(scope, Shell.signed_bytes(ordinal)))
    end

    attr_reader :puns, :key_misses

    # Generation and the simplest probe record protocol 3. The probe used to
    # record the legacy protocol, whose stream the sniffer reads back as
    # protocol 2 whenever the first rule's first draw is an integer, so its
    # failures did not replay.
    def stateful_protocol
      @replay.nil? ? 3 : Core.stateful_choice_protocol(@replay, @position, @remaining)
    end

    def stateful_feature_probability_raw(generated)
      @replay.nil? ? forced_integer(generated) : integer(0, 254)
    end

    def assume(condition)
      raise AssumptionRejected unless condition
    end

    # Fail this example unless condition holds.
    #
    # An ordinary property failure that shrinks and replays like any other,
    # with this call site as the bug's origin. A passing evaluation also
    # counts as covering the label, so a call site that may legitimately
    # never execute is fine on its own ("always or unreachable"), while
    # listing the label in `must_cover:` additionally fails a run that never
    # reached it.
    def always(label, condition)
      raise "always: \"#{label}\" did not hold" unless condition

      cover(label, true)
    end

    # Fail this example: the assertion is that nothing reaches this call.
    #
    # The failure shrinks and replays like any other, so the reported
    # counterexample is the simplest input that reaches the branch.
    def unreachable(label)
      raise "unreachable: \"#{label}\" was reached"
    end

    # Assert that condition holds in at least one valid example.
    #
    # A property passes vacuously when the branch it exists to test never
    # executes; sometimes turns that silent gap into a failure. The verdict
    # is per run, not per example, so a false condition here never fails the
    # current example — only a completed run in which it never held.
    def sometimes(label, condition)
      cover(label, condition)
    end

    # Assert that condition holds in at least percent% of valid examples.
    #
    # And at least once, whatever the rate. A label counts once per example
    # in which its condition held, however many times the call site ran.
    # Labels a run must observe even when the call site itself may never
    # execute are declared up front via the `must_cover:` option.
    def cover(label, condition, percent: 0)
      unless percent >= 0 && percent <= 100
        raise ArgumentError, "cover percent must be between 0 and 100"
      end

      family = root
      unless family.__send__(:coverage_held).key?(label)
        family.__send__(:coverage_order) << label
        family.__send__(:coverage_held)[label] = false
        family.__send__(:coverage_permille)[label] = 0
      end
      family.__send__(:coverage_held)[label] = true if condition
      permille = (percent * 10).to_i
      if permille > family.__send__(:coverage_permille)[label]
        family.__send__(:coverage_permille)[label] = permille
      end
      nil
    end

    # Draw from a generator.
    #
    # A named draw is reported in the falsifying example. The name is for the
    # report only: it records no choice, so naming a draw cannot change the
    # blob, the shrink order, or what any other language package replays.
    # Nested draws made by a composite generator stay anonymous, so only the
    # values a property actually names are rendered.
    def draw(generator, name: nil)
      outer = @generation_depth.zero?
      @generation_depth += 1
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond) if outer
      begin
        value = generator.do_draw(self)
        drawn << [name, value] unless name.nil?
        value
      ensure
        @generation_depth -= 1
        if outer
          elapsed = (
            Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond) - started
          ) / 1_000
          @generation_us = [((1 << 64) - 1), @generation_us + elapsed].min
        end
      end
    end

    attr_accessor :generation_us

    def note(message)
      root.__send__(:notes) << message.to_s
      nil
    end

    def start_span(label)
      parent = @span_stack.last
      span_id = spans.length
      spans << ChoiceSpan.new(
        start: draws.length,
        finish: draws.length,
        label: label,
        depth: @span_stack.length,
        parent: parent
      )
      @span_stack << span_id
      span_id
    end

    def stop_span(discarded: false)
      return if @span_stack.empty?

      span = spans[@span_stack.pop]
      span.finish = draws.length
      span.discarded = discarded
      nil
    end

    def open_span_depth
      @span_stack.length
    end

    def reset_open_spans_to(depth, discarded: true)
      stop_span(discarded: discarded) while @span_stack.length > depth
    end

    def close_open_spans
      stop_span until @span_stack.empty?
      # A clone has its own span structure, and the property may leave one open
      # on a child exactly as it may on the stream it was handed.
      draws.each { |draw| draw.child&.__send__(:close_open_spans) }
      nil
    end

    def check_choice_budget
      @replay = nil if @remaining.zero? && !@rng.nil?
      # The budget belongs to the family, not to one stream: upstream's cap is
      # on the whole pieced-together choice sequence, so a clone cannot buy
      # another 8,192 draws by starting a stream of its own.
      if @replay.nil? && Core.choice_budget_exhausted(root.flat_draws)
        raise ChoiceOverrun, "generated example exceeded the choice budget"
      end
    end

    def integer(minimum, maximum, shrink_towards: 0, key: nil, _uniform: false)
      raise ArgumentError, "minimum must be <= maximum" if minimum > maximum
      check_choice_budget

      position, simplest = resolve("integer", key)
      value =
        if simplest
          Shell.signed_int(
            Core.integer_simplest(
              Shell.signed_bytes(minimum),
              Shell.signed_bytes(maximum),
              Shell.signed_bytes(shrink_towards)
            )
          )
        elsif @replay.nil?
          if !_uniform && Core.integer_swarm_is_wide(minimum, maximum)
            count = Core.integer_boundary_count(minimum, maximum)
            family = root
            family.instance_variable_set(:@integer_swarm, @rng.rand(1 << 64)) if family.instance_variable_get(:@integer_swarm).nil?
            category = Core.integer_swarm_category(
              family.instance_variable_get(:@integer_swarm), @rng.rand(1000)
            )
            if category.zero?
              Core.integer_swarm_endpoint_candidate(minimum, maximum, @rng.rand(4))
            elsif category == 1 && count > 2
              Core.integer_boundary_candidate(minimum, maximum, 2 + @rng.rand(count - 2))
            elsif category == 2
              Core.integer_swarm_diffuse_candidate(
                minimum, maximum, @rng.rand(Core.integer_swarm_diffuse_count)
              ) || @rng.rand(minimum..maximum)
            else
              @rng.rand(minimum..maximum)
            end
          else
            # Narrow ranges are uniform: a boundary boost here over-picked the
            # ends of small ranges, i.e. the first and last option of a list
            # indexed by this draw.
            @rng.rand(minimum..maximum)
          end
        else
          low = Shell.signed_bytes(minimum)
          high = Shell.signed_bytes(maximum)
          @puns += 1 if Core.replay_integer_puns(@replay, position, low, high)
          Shell.signed_int(
            Core.replay_integer(
              @replay, position, low, high, Shell.signed_bytes(shrink_towards)
            )
          )
        end

      encoded = Core.serialize_integer_choice(Shell.signed_bytes(value))
      record(Draw.new(:integer, encoded, value, [minimum, maximum, shrink_towards], false, key))
      value
    end

    def boolean(key: nil)
      check_choice_budget
      position, simplest = resolve("boolean", key)
      value =
        if simplest
          false
        elsif @replay.nil?
          @rng.rand(2) == 1
        else
          @puns += 1 if Core.replay_boolean_puns(@replay, position)
          Core.replay_boolean(@replay, position)
        end
      record(Draw.new(:boolean, Core.serialize_boolean_choice(value), value, [], false, key))
      value
    end

    # Draw an identifier that is arbitrary but unique within this family.
    #
    # The identifier is recorded *by value*, so it keeps meaning the same
    # variable when unrelated earlier draws are deleted during shrinking —
    # which is the whole point of it, and what a positional index cannot do.
    # Generation always hands out the smallest unused identifier, and a
    # replayed identifier that is already in use is repaired to that same
    # smallest unused one.
    #
    # This is Hegel's draw_fresh_id (hegel-c 0.32.4).
    def fresh_id
      used = root.fresh_ids
      window_hi = Core.stateful_fresh_id_window(used.empty? ? 0 : used.max + 1)
      # Ascending order is load-bearing: the fold stops climbing at the first
      # gap, so walking the registry any other way would not answer with the
      # smallest unused identifier.
      fallback = used.sort.reduce(0) do |candidate, used_id|
        Core.stateful_fresh_id_fallback_step(candidate, used_id)
      end

      value = draw_identifier(window_hi, fallback, -> { fallback }) do |raw|
        Core.stateful_fresh_id_accepts(raw, window_hi, used.include?(raw)) ? raw : fallback
      end
      used << value
      value
    end

    # Draw one of members, recording the member itself.
    #
    # Recording the member rather than an index into the live set is what makes
    # a reference survive the deletion of *other* members: while the member it
    # names is still there it keeps naming it, and when that member goes the
    # reference slides to an earlier one rather than to whatever now occupies
    # some shifted position.
    #
    # This is Hegel's draw_from_set (hegel-c 0.32.4).
    def from_set(members)
      raise ArgumentError, "from_set requires at least one member" if members.empty?

      ordered = members.uniq.sort
      raise ArgumentError, "from_set requires nonnegative members" if ordered.first.negative?

      smallest = ordered.first
      used = root.fresh_ids
      window_hi = Core.stateful_set_choice_window(used.empty? ? 0 : used.max + 1)

      draw_identifier(window_hi, smallest, -> { ordered[@rng.rand(ordered.length)] }) do |raw|
        if Core.stateful_set_choice_accepts(raw, window_hi)
          ordered.reduce(smallest) do |best, candidate|
            Core.stateful_set_choice_better(candidate, raw, best) ? candidate : best
          end
        else
          smallest
        end
      end
    end

    # Draw a boolean that is true with the given probability. It is recorded as
    # an ordinary boolean choice: the weight biases generation only, so a blob
    # replays the same whatever probability produced it.
    def weighted(probability, key: nil)
      check_choice_budget
      position, simplest = resolve("boolean", key)
      value =
        if simplest
          false
        elsif @replay.nil?
          @rng.rand < probability
        else
          @puns += 1 if Core.replay_boolean_puns(@replay, position)
          Core.replay_boolean(@replay, position)
        end
      record(Draw.new(:boolean, Core.serialize_boolean_choice(value), value, [], false, key))
      value
    end

    def bytes(minimum = 0, maximum = 16, key: nil)
      raise ArgumentError, "require 0 <= minimum <= maximum" if minimum.negative? || minimum > maximum
      check_choice_budget

      position, simplest = resolve("bytes", key)
      value =
        if simplest
          Core.bytes_simplest(minimum)
        elsif @replay.nil?
          @rng.bytes(@rng.rand(minimum..maximum))
        else
          @puns += 1 if Core.replay_bytes_puns(@replay, position, minimum, maximum)
          Core.replay_bytes(@replay, position, minimum, maximum)
        end
      record(Draw.new(:bytes, Core.serialize_bytes_choice(value), value, [minimum, maximum], false, key))
      value
    end

    # Draw text of length [minimum, maximum] over an alphabet, by default every
    # Unicode scalar value.
    #
    # Shrinking is shortlex over the alphabet's shrink order, which puts "0"
    # through "Z" first, so a minimal counterexample reads as "0" rather than
    # as a control character.
    def string(minimum = 0, maximum = 16, alphabet: nil, key: nil)
      characters = alphabet || UNICODE
      raise ArgumentError, "require 0 <= minimum <= maximum" if minimum.negative? || minimum > maximum
      unless Core.alphabet_valid(characters)
        raise ArgumentError, "alphabet must be a canonical non-empty interval set"
      end

      check_choice_budget
      position, simplest = resolve("string", key)
      packed =
        if simplest
          Core.string_simplest(characters, minimum)
        elsif @replay.nil?
          span = Core.text_rank_span(characters, @rng.rand(1000) < Core.text_bias_threshold)
          Array.new(@rng.rand(minimum..maximum)) do
            Core.alphabet_shrink_codepoint(characters, @rng.rand(span))
          end.pack("V*")
        else
          if Core.replay_string_puns(@replay, position, characters, minimum, maximum)
            @puns += 1
          end
          Core.replay_string(@replay, position, characters, minimum, maximum)
        end
      value = Shell.unpack_codepoints(packed)
      record(Draw.new(
        :string,
        Core.serialize_string_choice_packed(packed.bytesize / 4, packed),
        value,
        [characters, minimum, maximum],
        false,
        key
      ))
      value
    end

    # Draw an IEEE-754 binary64 value with portable replay and shrinking.
    # Bounds use sign-aware ordering, so -0.0 is strictly below +0.0.
    def float(
      minimum = -Float::INFINITY,
      maximum = Float::INFINITY,
      allow_nan: false,
      allow_infinity: false,
      smallest_nonzero_magnitude: 0.0,
      key: nil
    )
      unless Core.float_generation_spec_valid(
        minimum, maximum, allow_nan, allow_infinity, smallest_nonzero_magnitude
      )
        raise ArgumentError, "invalid float bounds"
      end
      unit = Core.float_unit(
        minimum, maximum, allow_nan, allow_infinity, smallest_nonzero_magnitude
      )
      raise ArgumentError, "float configuration admits no values" if unit.nil?
      check_choice_budget

      position, simplest = resolve("float", key)
      value =
        if simplest
          Core.float_simplest(
            minimum, maximum, allow_nan, allow_infinity, smallest_nonzero_magnitude
          )
        elsif @replay.nil?
          # One family-wide category mixture, then one roll per draw. A
          # category the spec rules out yields to the default draw, so its
          # mass is never handed to a neighbouring category.
          family = root
          family.instance_variable_set(:@float_swarm, @rng.rand(1 << 64)) if family.instance_variable_get(:@float_swarm).nil?
          category = Core.float_swarm_category(
            family.instance_variable_get(:@float_swarm), @rng.rand(Core.float_swarm_roll_span)
          )
          words = Array.new(5) { @rng.rand(1 << 64) }
          Core.float_category_candidate(
            category, minimum, maximum, allow_nan, allow_infinity,
            smallest_nonzero_magnitude, *words
          ) || Core.float_default_candidate(
            minimum, maximum, allow_nan, allow_infinity,
            smallest_nonzero_magnitude, *Array.new(4) { @rng.rand(1 << 64) }
          )
        else
          if Core.replay_float_puns(
            @replay, position,
            minimum, maximum, allow_nan, allow_infinity,
            smallest_nonzero_magnitude
          )
            @puns += 1
          end
          Core.replay_float(
            @replay, position,
            minimum, maximum, allow_nan, allow_infinity,
            smallest_nonzero_magnitude
          ) || unit
        end

      params = [minimum, maximum, allow_nan, allow_infinity, smallest_nonzero_magnitude]
      record(Draw.new(:float, Core.serialize_float_choice(value), value, params, false, key))
      value
    end

    def forced_integer(value)
      check_choice_budget
      advance_replay("forced integer") unless @replay.nil?
      encoded = Core.serialize_integer_choice(Shell.signed_bytes(value))
      record(Draw.new(:integer, encoded, value, [value, value, value], true, nil))
      value
    end

    def forced_boolean(value)
      check_choice_budget
      advance_replay("forced boolean") unless @replay.nil?
      record(Draw.new(:boolean, Core.serialize_boolean_choice(value), value, [], true, nil))
      value
    end

    # Draw a variable-length sequence of values from one generator.
    #
    # The length is never a choice of its own. Each iteration draws a single
    # "another element?" boolean inside a span that also holds that element's
    # own choices, which is what makes a collection structurally shrinkable:
    # deleting the span removes exactly one element and leaves the rest of the
    # stream framed correctly. Truncation falls out of the same shape —
    # lowering one of those booleans to false ends the sequence there.
    #
    # The decision itself lives in the core (ir/many.zir); this loop only
    # supplies entropy and records spans.
    def collect(element, min_size = 0, max_size = nil, label = "collection.element")
      raise ArgumentError, "min_size must be >= 0" if min_size.negative?

      has_max = !max_size.nil?
      bound = has_max ? max_size : 0
      raise ArgumentError, "max_size must be >= min_size" if has_max && bound < min_size

      probability = Core.length_p_continue(min_size, bound, has_max)
      draws_choice = Core.many_draws_choice(min_size, bound, has_max)
      values = []
      loop do
        start_span(label)
        forced = Core.many_forced_value(false, values.length, min_size, bound, has_max, probability)
        more =
          if !draws_choice
            # Bounds coincide: upstream draws nothing at all here.
            values.length < min_size
          elsif forced.nil?
            weighted(probability)
          else
            forced_boolean(forced)
          end
        unless more
          stop_span(discarded: true)
          return values
        end
        # An open span is closed for us when the execution unwinds.
        values << draw(element)
        stop_span
      end
    end

    # What a rejected element costs a unique collection. Defined by
    # ir/many.zir::many_reject_action.
    REJECT_RETRY = 0
    REJECT_STOP = 1
    REJECT_INVALID = 2

    # Draw a variable-length sequence whose elements are all distinct.
    #
    # Same pacing as #collect, with one extra decision layered on: what a
    # duplicate costs. Upstream spells a unique collection as a *filtered*
    # element draw inside the same "another element?" loop, so this does too.
    # Each element gets up to +filter_retry_allowed+ candidates, each in its own
    # span that is discarded when the candidate is already present — the choices
    # stay in the stream, so a replay walks the same positions, but the shrinker
    # may delete them freely.
    #
    # When every candidate for one element is a duplicate the *element* is
    # rejected rather than the example, and +many_reject_action+ decides what
    # that costs: retry, stop the collection where it is, or — when the
    # collection cannot reach its own min_size — reject the example the way a
    # failed assumption does. Both rules live in ir/many.zir.
    #
    # +key+ maps an element to the value uniqueness is judged on, which is what
    # separates a set (identity) from a mapping keyed by one field.
    def collect_unique(element, key = nil, min_size = 0, max_size = nil,
                       label = "collection.element")
      raise ArgumentError, "min_size must be >= 0" if min_size.negative?

      has_max = !max_size.nil?
      bound = has_max ? max_size : 0
      raise ArgumentError, "max_size must be >= min_size" if has_max && bound < min_size

      probability = Core.length_p_continue(min_size, bound, has_max)
      draws_choice = Core.many_draws_choice(min_size, bound, has_max)
      values = []
      seen = {}
      rejections = 0
      force_stop = false
      loop do
        start_span(label)
        forced = Core.many_forced_value(force_stop, values.length, min_size, bound, has_max,
                                        probability)
        more =
          if !draws_choice
            # Bounds coincide: upstream draws nothing at all here.
            values.length < min_size
          elsif forced.nil?
            weighted(probability)
          else
            forced_boolean(forced)
          end
        unless more
          stop_span(discarded: true)
          return values
        end
        accepted = nil
        attempts = 0
        while Core.filter_retry_allowed(attempts)
          start_span("collection.candidate")
          candidate = draw(element)
          attempts += 1
          fingerprint = key.nil? ? candidate : key.call(candidate)
          if seen.key?(fingerprint)
            stop_span(discarded: true)
            next
          end
          stop_span
          accepted = [candidate, fingerprint]
          break
        end
        if accepted.nil?
          stop_span(discarded: true)
          rejections += 1
          case Core.many_reject_action(rejections, values.length, min_size)
          when REJECT_INVALID then raise AssumptionRejected
          when REJECT_STOP then force_stop = true
          end
          next
        end
        candidate, fingerprint = accepted
        seen[fingerprint] = true
        values << candidate
        stop_span
      end
    end

    def finish
      nil
    end

    def serialized
      Core.choice_list_header(draws.length) + draws.map { |draw| Shell.entry(draw) }.join
    end


    # Engine-only operations. Cross-object callers use __send__ explicitly;
    # properties and custom generators use the public draw/span API.
    private :draws, :spans, :notes, :drawn,
            :coverage_order, :coverage_held, :coverage_permille, :costs,
            :targets, :root, :depth, :record,
            :total_cost, :stateful_protocol, :stateful_feature_probability_raw, :generation_us,
            :open_span_depth, :reset_open_spans_to, :close_open_spans, :check_choice_budget,
            :fresh_id, :from_set, :forced_integer, :forced_boolean,
            :collect, :collect_unique, :finish, :serialized,
            :puns, :key_misses, :generation_us=
    private_constant :MAX_CLONE_DEPTH, :REJECT_RETRY, :REJECT_STOP, :REJECT_INVALID

    private

    # Record one identifier choice for #fresh_id or #from_set: an integer in
    # [0, window_hi].
    #
    # Identifier draws differ from #integer only in how a replayed value is
    # resolved — an ordinary integer puns to the nearest legal value, while an
    # identifier is *repaired* onto one the pool still holds — so what reaches
    # the stream is an ordinary integer entry and nothing downstream (the wire
    # format, the shrinker, the indexers) has to know these exist. The repaired
    # value is what gets recorded, which is what lets a replayed stream heal
    # rather than drift.
    def draw_identifier(window_hi, simplest_value, generate, &repair)
      check_choice_budget

      position, simplest = resolve("integer", nil)
      value =
        if simplest
          simplest_value
        elsif @replay.nil?
          generate.call
        else
          low = Shell.signed_bytes(0)
          high = Shell.signed_bytes(window_hi)
          # A recorded value outside the window is *punned*, not repaired.
          # Repair is for a value that named a member which has since gone, and
          # it slides towards an earlier one; a value that was never in the
          # window names nothing, so it falls back to the simplest member the
          # way every other out-of-range replay value does. Reading
          # replay_integer first would lose the distinction — it clamps to the
          # window, which would send a runaway value to the *largest* member
          # rather than the smallest.
          if Core.replay_integer_puns(@replay, position, low, high)
            @puns += 1
            simplest_value
          else
            repair.call(
              Shell.signed_int(
                Core.replay_integer(@replay, position, low, high, Shell.signed_bytes(0))
              )
            )
          end
        end

      encoded = Core.serialize_integer_choice(Shell.signed_bytes(value))
      record(Draw.new(:integer, encoded, value, [0, window_hi, 0], false, nil))
      value
    end

    # Index the replay stream by key, innermost entry offset first.
    def key_offsets
      return @keyed unless @keyed.nil?

      offsets = {}
      position = 4
      remaining = Core.choice_stream_count(@replay)
      while remaining.positive?
        finish = Core.choice_entry_end(@replay, position, 0)
        break if finish.zero?

        key = Core.keyed_entry_key(@replay, position)
        unless key.nil?
          (offsets[key] ||= []) << Core.keyed_entry_inner(@replay, position)
        end
        position = finish
        remaining -= 1
      end
      @keyed = offsets
    end

    # Where this draw's recorded entry sits, or nil to use the simplest value.
    #
    # An unkeyed draw takes the next positional entry and overruns when there is
    # none. A keyed draw takes the next entry recorded under its name and falls
    # back to the simplest value when the stream has none — a missing name is an
    # edit to the property, not a malformed blob.
    def replay_position(kind, key)
      return advance_replay(kind) if key.nil?

      pending = key_offsets[key]
      if pending.nil? || pending.empty?
        root.count_key_miss!
        return nil
      end
      pending.shift
    end

    # Where to read this draw from, and whether to use its simplest value.
    def resolve(kind, key)
      return [nil, true] if @simplest
      return [nil, false] if @replay.nil?

      position = replay_position(kind, key)
      [position, position.nil?]
    end

    def advance_replay(kind)
      loop do
        raise ReplayOverrun, "replay ended before #{kind} draw" if @replay.nil? || @remaining.zero?

        position = @position
        ending = Core.choice_entry_end(@replay, position, 0)
        raise InvalidReplay, "invalid replay entry at offset #{position}" if ending.zero?

        @position = ending
        @remaining -= 1
        # A named entry belongs to the draw that names it, wherever that draw
        # happens to fall. The positional cursor steps over it, so adding or
        # removing keyed draws cannot shift unkeyed ones.
        return position if Core.keyed_entry_key(@replay, position).nil?
      end
    end
  end

  module Shell
    module_function

    def signed_bytes(value)
      width = 1
      width += 1 until value >= -(1 << (width * 8 - 1)) && value < (1 << (width * 8 - 1))
      unsigned = value.negative? ? (1 << (width * 8)) + value : value
      Array.new(width) { |index| (unsigned >> (index * 8)) & 0xff }.pack("C*")
    end

    def signed_int(value)
      return 0 if value.empty?

      unsigned = value.bytes.each_with_index.sum { |byte, index| byte << (index * 8) }
      bits = value.bytesize * 8
      value.getbyte(-1) >= 0x80 ? unsigned - (1 << bits) : unsigned
    end

    def execute(property, rng: nil, replay: nil, simplest: false)
      test_case = TestCase.new(rng: rng, replay: replay, simplest: simplest)
      begin
        result = property.call(test_case)
        test_case.__send__(:finish)
        raise RuntimeError, "property returned false" if result == false
        [nil, test_case]
      rescue Interrupt, SystemExit
        raise
      rescue Exception => error # rubocop:disable Lint/RescueException
        [error, test_case]
      ensure
        test_case.__send__(:close_open_spans)
      end
    end

    # A schedule slot that maps to no legal value. Distinct from the schedule
    # ending, because the search should step over it rather than give up on
    # the choice.
    SCHEDULE_MISS = Object.new

    # The compiled schedule is defined over u64 indexes; byte draws can sit
    # beyond that, and saturating keeps their earliest (most useful)
    # candidates reachable.
    U64_MAX = (1 << 64) - 1

    # The choice's unconstrained index for shortlex comparison.
    def draw_sort_index(draw)
      case draw.kind
      when :boolean
        Core.boolean_to_index(draw.value)
      when :integer
        minimum, maximum, target = draw.params
        bounds = [minimum, maximum, target].map { |value| signed_bytes(value) }
        Core.integer_to_index(*bounds, signed_bytes(draw.value))
      when :bytes
        minimum, = draw.params
        Core.bytes_to_index(minimum, draw.value)
      when :string
        characters, minimum, = draw.params
        Core.string_to_index(characters, minimum, Shell.pack_codepoints(draw.value))
      when :float
        Core.float_choice_to_index(*draw.params, draw.value)
      end
    end

    # Where a draw currently sits in its own shrink schedule.
    def draw_index(draw)
      return nil if draw.forced

      encoded = draw_sort_index(draw)
      encoded.nil? ? nil : [signed_int(encoded), U64_MAX].min
    end

    # The draw kinds the targeting hill climber can step. Strings have no
    # sensible "one larger", clones are streams rather than values, and a
    # forced draw is checked separately.
    def climbable_draw?(draw)
      !draw.forced && draw.child.nil? &&
        [:integer, :boolean, :float, :bytes].include?(draw.kind)
    end

    # The draw stepped by delta, or nil when the stepped value is not
    # representable within the draw's own constraints. Which values are
    # reachable is compiled (ir/targeting.zir @targeting_step_*); this only
    # re-encodes the answer as a stream entry.
    def step_draw(draw, delta)
      case draw.kind
      when :integer
        minimum, maximum, = draw.params
        stepped = Core.targeting_step_integer(
          signed_bytes(minimum), signed_bytes(maximum), signed_bytes(draw.value), delta
        )
        return nil if stepped.nil?

        Draw.new(:integer, Core.serialize_integer_choice(stepped), signed_int(stepped),
                 draw.params, false, draw.key)
      when :boolean
        stepped = Core.targeting_step_boolean(draw.value, delta)
        return nil if stepped.nil?

        Draw.new(:boolean, Core.serialize_boolean_choice(stepped), stepped, [], false, draw.key)
      when :float
        stepped = Core.targeting_step_float(*draw.params, draw.value, delta)
        return nil if stepped.nil?

        Draw.new(:float, Core.serialize_float_choice(stepped), stepped, draw.params, false,
                 draw.key)
      when :bytes
        minimum, maximum = draw.params
        stepped = Core.targeting_step_bytes(minimum, maximum, draw.value, delta)
        return nil if stepped.nil?

        Draw.new(:bytes, Core.serialize_bytes_choice(stepped), stepped, draw.params, false,
                 draw.key)
      end
    end

    # An integer draw at the ordinal-th extra lowering candidate, or nil.
    #
    # The index schedule bisects, which finds the edge of an interval; a sparse
    # failing set such as the positive multiples of 1000 is not one, and from
    # 10**9 the bisection stops at 875000. The divisions and trailing-zeros
    # moves that carry on from there are compiled (@integer_shrink_extra); this
    # only re-encodes the value they choose.
    def integer_extra_draw(draw, ordinal)
      return nil if draw.kind != :integer || draw.forced

      bounds = draw.params.map { |value| signed_bytes(value) }
      value = Core.integer_shrink_extra(*bounds, signed_bytes(draw.value), ordinal)
      return nil if value.nil?

      Draw.new(:integer, Core.serialize_integer_choice(value), signed_int(value), draw.params,
               false, draw.key)
    end

    # Where a draw sits and the largest index it could move to, for the raise
    # pass, as [current, largest]; nil for a draw the pass leaves alone.
    #
    # Upstream raises every node but a sequence, so strings and byte strings
    # are skipped — their index bundles length and content, and a larger one is
    # a longer value — and so are clones, which carry a stream rather than a
    # value, and forced draws, which are not this stream's to change.
    def raise_bounds(draw)
      return nil if draw.forced || !draw.child.nil?

      largest =
        case draw.kind
        when :boolean then Core.boolean_max_index
        when :integer
          minimum, maximum, = draw.params
          Core.integer_max_index(signed_bytes(minimum), signed_bytes(maximum))
        when :float then Core.float_choice_max_index
        end
      return nil if largest.nil?

      current = draw_index(draw)
      return nil if current.nil?

      [current, [signed_int(largest), U64_MAX].min]
    end

    # What makes two draws duplicates of each other.
    #
    # Upstream groups by (choice type, value) and lowers the group using the
    # first member's constraints, accepting that a member with different
    # constraints may reject the shared value. Grouping by the *index* instead
    # is the same idea in the coordinate the schedule already walks: two draws
    # with equal bounds share an index exactly when they share a value, and a
    # member whose bounds differ is rebuilt for its own bounds or misses. A
    # forced draw is never a member — it has no index and may not be rewritten.
    def draw_group_key(draw)
      index = draw_index(draw)
      index.nil? ? nil : [draw.kind, index]
    end

    # Rebuild every choice in a span at its simplest value, and report how many
    # of them the pass was actually able to move.
    #
    # This is upstream's try_trivial_spans. Per-choice descent walks one draw at
    # a time and stops the moment a candidate stops failing, so a span whose
    # choices only fail *together* at their simplest values is out of its reach
    # — and the all-simplest probe does not help either, because it collapses
    # the whole example rather than one span of it. A forced draw is left alone,
    # as in every other pass, and a draw already at index 0 is copied rather
    # than rebuilt.
    def trivial_span_candidate(draws, span)
      trial = draws.dup
      rewritable = 0
      (span.start...[span.finish, draws.length].min).each do |at|
        index = draw_index(draws[at])
        next if index.nil? || index.zero?

        candidate = draw_at_index(draws[at], 0)
        next if candidate.equal?(SCHEDULE_MISS)

        trial[at] = candidate
        rewritable += 1
      end
      [trial, rewritable]
    end

    # A string draw with the character at one position removed.
    #
    # The whole-value index bundles length and content into one number, and the
    # downward search over it converges on the wrong end of the interval: from
    # "abb" over an "abcdef" alphabet it probes eleven candidates and never
    # reaches "bb", which sits far below. Removing a character is the candidate
    # that search cannot produce.
    def shorten_string(draw, position)
      return nil unless draw.kind == :string
      return nil if draw.forced

      _characters, min_size, = draw.params
      value = Core.string_drop_character(Shell.pack_codepoints(draw.value), min_size, position)
      return nil if value.nil?

      candidate = draw.dup
      candidate.value = Shell.unpack_codepoints(value)
      candidate.encoded = Core.serialize_string_choice_packed(value.length / 4, value)
      candidate
    end

    # A string draw with every copy of one repeated character lowered.
    #
    # A string draw carries a single whole-value index, so the per-choice
    # schedule can only slide the entire value along one linear order. A
    # property that depends on two *characters* of that value agreeing is the
    # case it cannot serve — M12's shape, one level down and inside a single
    # draw.
    def lower_characters(draw, ordinal)
      return nil unless draw.kind == :string
      return nil if draw.forced

      characters, = draw.params
      packed = Shell.pack_codepoints(draw.value)
      rank = Core.string_duplicate_rank(characters, packed)
      return nil if rank.nil?

      target = Core.shrink_candidate_at(rank, ordinal)
      return nil if target.nil?

      value = Core.string_replace_rank(characters, packed, rank, target)
      return nil if value.nil?

      candidate = draw.dup
      candidate.value = Shell.unpack_codepoints(value)
      candidate.encoded = Core.serialize_string_choice_packed(value.length / 4, value)
      candidate
    end

    # The ordinal-th span strictly nested inside spans[at].
    #
    # Upstream's pass_to_descendant picks a random descendant; a cursor machine
    # has no chooser, so the ancestor is the cursor and the descendant is the
    # ordinal. Spans are recorded in the order they open, so scanning forward
    # from the ancestor gives a stable enumeration in every language.
    def descendant_span(spans, at, ordinal)
      ancestor = spans[at]
      return nil if ancestor.discarded || ancestor.finish <= ancestor.start

      seen = 0
      ((at + 1)...spans.length).each do |other|
        candidate = spans[other]
        next if candidate.start < ancestor.start || candidate.finish > ancestor.finish
        next if candidate.discarded || candidate.depth <= ancestor.depth
        next unless Core.shrink_descendant_worthwhile(
          ancestor.finish - ancestor.start, candidate.finish - candidate.start
        )
        return candidate if seen == ordinal

        seen += 1
      end
      nil
    end

    # The span that should trade places with spans[at].
    #
    # Upstream groups a span's children by label and sorts the group; taking
    # only the *next* member makes each request one adjacent swap, and
    # repeating it until nothing moves sorts the group the same way. A
    # discarded span is never a member: its choices are a rejected candidate's
    # debris, so its position carries no meaning to canonicalize.
    # The choices a paid deletion of spans[at] removes, as [start, finish,
    # widened], or nil.
    #
    # A span of two or more choices is deleted exactly, as the deletion pass
    # already tried on its own. A single-choice span takes upstream's extent:
    # the span with the spanless choice before it, or else stretched to the
    # start of the next span. A discarded span is never a candidate — its
    # choices are a rejected candidate's debris or a collection's stop marker,
    # and paying for their deletion buys nothing — and neither is an extent
    # covering the whole stream.
    def paid_extent(draws, spans, at)
      span = spans[at]
      return nil if span.discarded || span.finish <= span.start || span.finish > draws.length

      start = span.start
      finish = span.finish
      widened = false
      if finish - start < 2
        widened = true
        preceded = start.positive? && spans.none? { |other| other.finish == start && other.start < start }
        if preceded
          start -= 1
        else
          finish = spans.map(&:start).select { |other| other >= span.finish }.min || draws.length
          return nil if finish <= span.finish
        end
      end
      return nil if start.zero? && finish == draws.length

      [start, finish, widened]
    end

    # The draw that pays for deleting spans[at]: the first one after the
    # structure enclosing it, or nil.
    #
    # Upstream takes the innermost ancestor span reaching past the deletion. A
    # zizek collection opens no span of its own — its elements are a run of
    # adjacent sibling spans sharing a label, ending in the discarded span of
    # its final "no more" choice — so that run is what plays the part of the
    # list, and only a span outside any such run falls back to its ancestors.
    def paid_follower(spans, at, finish, draw_count)
      span = spans[at]
      run_end = span.finish
      extended = false
      ((at + 1)...spans.length).each do |other|
        candidate = spans[other]
        next if candidate.parent != span.parent
        break if candidate.label != span.label || candidate.start != run_end

        run_end = candidate.finish
        extended = true
      end
      boundary = nil
      if extended
        boundary = run_end
      else
        parent = span.parent
        until parent.nil?
          if spans[parent].finish > finish
            boundary = spans[parent].finish
            break
          end
          parent = spans[parent].parent
        end
      end
      return nil if boundary.nil? || boundary < finish || boundary >= draw_count

      boundary
    end

    # The paying draw moved one step: an integer down or up, a boolean to the
    # side the step names, a string one character shorter. SCHEDULE_MISS when
    # this draw cannot take this step, so the pass moves to the next one
    # without running the property.
    def nudge_draw(draw, step)
      return SCHEDULE_MISS if draw.forced

      stepped =
        case draw.kind
        when :integer
          step_draw(draw, step)
        when :boolean
          candidate = step_draw(draw, step)
          candidate.nil? || candidate.value == draw.value ? nil : candidate
        when :string
          step.negative? ? shorten_string(draw, draw.value.length - 1) : nil
        end
      stepped.nil? ? SCHEDULE_MISS : stepped
    end

    def next_sibling(spans, at)
      span = spans[at]
      return nil if span.discarded || span.finish <= span.start

      ((at + 1)...spans.length).each do |other|
        candidate = spans[other]
        next if candidate.discarded || candidate.parent != span.parent
        next if candidate.label != span.label
        next if candidate.finish <= candidate.start || candidate.start < span.finish

        return other
      end
      nil
    end

    # Where a draw sits in its schedule, for the adjacent-pair pass.
    #
    # Upstream's lower_integers_together takes integer nodes only, and so does
    # this: the shift it makes is meaningful in value space precisely because
    # an integer's index is its distance from its own shrink target. A byte
    # string's index is a shortlex position, and shifting two of those by a
    # shared amount preserves nothing a property could depend on.
    def pair_index(draw)
      draw.kind == :integer ? draw_index(draw) : nil
    end

    # Choice-count-first shortlex: shorter streams win, then the first lower
    # per-choice index wins.
    def draws_simpler?(candidate, current)
      draws_compare(candidate, current).negative?
    end

    # Order two draw lists: negative when candidate is the simpler of the two.
    #
    # The count that decides first is the *flattened* one, so a candidate that
    # removes a choice from inside a clone is simpler even though the parent's
    # own entry count has not moved — without that, a nested shrink could never
    # make progress the accept rule would keep. A clone is then compared by its
    # own stream, recursively, which is the same rule one level down.
    def draws_compare(candidate, current)
      left = Shell.flat_draw_count(candidate)
      right = Shell.flat_draw_count(current)
      return left < right ? -1 : 1 unless left == right
      unless candidate.length == current.length
        return candidate.length < current.length ? -1 : 1
      end

      candidate.zip(current).each do |candidate_draw, current_draw|
        if !candidate_draw.child.nil? || !current_draw.child.nil?
          return 1 if candidate_draw.child.nil? || current_draw.child.nil?

          order = draws_compare(candidate_draw.child.__send__(:draws), current_draw.child.__send__(:draws))
          return order unless order.zero?

          next
        end
        candidate_index = draw_sort_index(candidate_draw)
        current_index = draw_sort_index(current_draw)
        return 1 if candidate_index.nil? || current_index.nil?

        order = Core.signed_compare_le(candidate_index, current_index)
        return order unless order.zero?
      end
      0
    end

    # Rebuild a draw at a schedule index, or report a miss.
    #
    # The rebuilt draw keeps its key: a lowered candidate that lost its name
    # would be looked up positionally on the next execution, so every candidate
    # for a keyed draw would be rejected and nothing would shrink.
    def draw_at_index(draw, index)
      case draw.kind
      when :boolean
        value = Core.boolean_from_index(signed_bytes(index))
        return SCHEDULE_MISS if value.nil?

        Draw.new(:boolean, Core.serialize_boolean_choice(value), value, draw.params, false, draw.key)
      when :integer
        minimum, maximum, target = draw.params
        bounds = [minimum, maximum, target].map { |value| signed_bytes(value) }
        value_bytes = Core.integer_from_index(*bounds, signed_bytes(index))
        return SCHEDULE_MISS if value_bytes.nil?

        Draw.new(
          :integer,
          Core.serialize_integer_choice(value_bytes),
          signed_int(value_bytes),
          draw.params,
          false,
          draw.key
        )
      when :bytes
        minimum, maximum = draw.params
        value = Core.bytes_from_index(minimum, maximum, signed_bytes(index))
        return SCHEDULE_MISS if value.nil?

        Draw.new(:bytes, Core.serialize_bytes_choice(value), value, draw.params, false, draw.key)
      when :string
        characters, minimum, maximum = draw.params
        packed = Core.string_from_index(characters, minimum, maximum, signed_bytes(index))
        return SCHEDULE_MISS if packed.nil?

        Draw.new(
          :string,
          Core.serialize_string_choice_packed(packed.bytesize / 4, packed),
          Shell.unpack_codepoints(packed),
          draw.params,
          false,
          draw.key
        )
      when :float
        value = Core.float_choice_from_index(*draw.params, signed_bytes(index))
        return SCHEDULE_MISS if value.nil?

        Draw.new(:float, Core.serialize_float_choice(value), value, draw.params, false, draw.key)
      else
        SCHEDULE_MISS
      end
    end

    # Every shrink candidate for a draw, in schedule order.
    def candidate_draws(draw)
      current = draw_index(draw)
      return [] if current.nil?

      candidates = []
      ordinal = 0
      loop do
        index = Core.shrink_candidate_at(current, ordinal)
        break if index.nil?

        candidate = draw_at_index(draw, index)
        candidates << candidate unless candidate.equal?(SCHEDULE_MISS)
        ordinal += 1
      end
      candidates
    end

    def serialized_draws(draws)
      Core.choice_list_header(draws.length) + draws.map { |draw| Shell.entry(draw) }.join
    end

    class ChoiceTree
      def initialize
        @terminal = false
        @children = {}
      end

      def include?(path)
        node = self
        path.each_byte do |byte|
          node = node.child(byte)
          return false if node.nil?
        end
        node.terminal?
      end

      def insert(path)
        node = self
        path.each_byte { |byte| node = node.child_or_insert(byte) }
        node.mark_terminal
      end

      protected

      def child(byte)
        @children[byte]
      end

      def child_or_insert(byte)
        @children[byte] ||= ChoiceTree.new
      end

      def terminal?
        @terminal
      end

      def mark_terminal
        @terminal = true
      end
    end

    def span_mutation_candidates(draws, spans, rng)
      return [] if draws.any? { |draw| !draw.key.nil? }

      grouped = Hash.new { |hash, label| hash[label] = [] }
      spans.each do |span|
        if !span.discarded && span.finish > span.start && span.finish <= draws.length
          grouped[span.label] << [span.start, span.finish]
        end
      end
      original = serialized_draws(draws)
      candidates = []
      labels = grouped.keys.select { |label| grouped[label].uniq.length >= 2 }.sort
      return [] if labels.empty?

      Core.mutation_attempt_count.times do |attempt|
        randomized = Core.mutation_attempt_randomized(attempt)
        group_index = randomized ? Core.mutation_index(labels.length, rng.rand(1 << 64)) : 0
        break if group_index.nil?

        label = labels[group_index]
        ranges = grouped[label].uniq.sort
        first = randomized ? Core.mutation_index(ranges.length, rng.rand(1 << 64)) : 0
        second = randomized ? Core.mutation_distinct_index(ranges.length, first, rng.rand(1 << 64)) : 1
        next if second.nil?

        a, b = ranges[first], ranges[second]
        a, b = b, a if (a <=> b).positive?
        a_start, a_end = a
        b_start, b_end = b
        raw = Core.choice_mutate_ranges(
          original, a_start, a_end, b_start, b_end,
          Core.mutation_use_first(randomized ? rng.rand(1 << 64) : attempt)
        )
        next if raw.nil? || raw == original || candidates.include?(raw)

        candidates << raw
      end
      candidates
    end

    # One label's run-level coverage. Declared requirements are registered
    # before the first example and observed-only labels in first-observation
    # order, which is also the order verdicts are checked in — so shells that
    # agree on the counters agree on the label a failure names.
    CoverageCounter = Struct.new(:label, :permille, :observed)

    # Outcome tags are defined by ir/lifecycle.zir. Deriving one from a host
    # exception is the shell's job; deciding what it means is the core's.
    OUTCOME_VALID = 0
    OUTCOME_REJECTED = 1
    OUTCOME_OVERRUN = 2
    OUTCOME_INVALID = 3
    OUTCOME_INTERESTING = 4

    def classify(error)
      return OUTCOME_VALID if error.nil?
      return OUTCOME_REJECTED if error.is_a?(AssumptionRejected)
      return OUTCOME_OVERRUN if error.is_a?(ReplayOverrun) || error.is_a?(ChoiceOverrun)
      return OUTCOME_INVALID if error.is_a?(InvalidReplay)

      OUTCOME_INTERESTING
    end

    # The backtrace prefix of a frame inside this shell.
    SHELL_FRAME = "#{__FILE__}:"

    # Identify which bug an exception represents: its class and where it was
    # raised, never its message, since a message that quotes a drawn value
    # would change on every shrink step and stop the search immediately.
    #
    # The raise site is the innermost frame outside this shell: an assertion
    # the shell raises on the property's behalf — always, unreachable — would
    # otherwise be identified by the shell's one raise line, which every such
    # assertion in the property would share, and the shrinker would migrate
    # between them.
    def interesting_origin(error)
      backtrace = error.backtrace
      site = backtrace&.find { |frame| !frame.start_with?(SHELL_FRAME) } || backtrace&.first
      [error.class, site]
    end

    # Whether an outcome is a failure of the bug being shrunk. Accepting any
    # failure lets the search migrate to an unrelated bug that happens to be
    # easier to reach, and then report a minimal counterexample for a bug the
    # run never found.
    def failure?(error, origin)
      outcome = classify(error)
      return false unless Core.outcome_is_failure(outcome)

      matches = origin.nil? || interesting_origin(error) == origin
      Core.shrink_accept(outcome, matches)
    end

    # Internal control flow: the shrinker replayed an example that had failed
    # and it did not fail the same way. The run reports it as Flaky.
    class FlakyReplay < StandardError; end

    # Request kinds and feedback codes are defined by ir/lifecycle.zir.
    PHASE_BASELINE = 0

    REQUEST_DONE = 0
    REQUEST_BASELINE = 1
    REQUEST_DELETE_SPAN = 2
    REQUEST_LOWER = 3
    REQUEST_VERIFY = 4
    REQUEST_LOWER_DUPLICATES = 5
    REQUEST_LOWER_PAIR = 6
    REQUEST_REORDER = 7
    REQUEST_TRIVIAL_SPAN = 8
    REQUEST_DESCENDANT = 9
    REQUEST_LOWER_CHARACTERS = 10
    REQUEST_SHORTEN_STRING = 11
    REQUEST_DELETE_PAID = 12
    REQUEST_RAISE = 13

    FEEDBACK_SKIP = 0
    FEEDBACK_REJECTED = 1
    FEEDBACK_ACCEPTED = 2

    # Serve the generated shrink schedule until it reports done.
    #
    # The search order lives in the core; this loop only runs the property,
    # maps the host's outcome onto a feedback code, and turns a request into
    # a concrete candidate. A zero cap leaves the search unbounded.
    # One execution of a candidate: the whole family it produced, and the case
    # whose draws the candidate stream became. The two differ only when the
    # level being shrunk is a clone's stream rather than the family's own.
    ShrinkRun = Struct.new(:family, :subject, :error)

    # The level that shrinks the stream the property was handed.
    def family_level(property)
      lambda do |candidate|
        error, test_case = execute(property, replay: candidate)
        ShrinkRun.new(test_case, test_case, error)
      end
    end

    # Serve the generated shrink schedule over one level until it reports done.
    # The last value is how many shrinks the sweep accepted, which is what its
    # cap counts.
    def shrink_stream(property, level, family, subject, origin = nil, max_shrinks: 0, max_stall: 0)
      draws = subject.__send__(:draws).dup
      spans = subject.__send__(:spans).dup
      family_draws = family.__send__(:draws).dup
      cost = family.__send__(:total_cost)
      best = family
      best_subject = subject
      accepted = false
      verified = nil
      schedule_at = -1
      schedule_index = nil
      schedule_count = 0

      adopt = lambda do |run|
        # accepted means *improved*, not merely adopted: the baseline replays
        # the example the caller already had, and a caller that treated that as
        # progress would descend into the same clone forever.
        if run.family.__send__(:total_cost) < cost || draws_compare(run.family.__send__(:draws), family_draws).negative?
          accepted = true
        end
        draws = run.subject.__send__(:draws).dup
        spans = run.subject.__send__(:spans).dup
        family_draws = run.family.__send__(:draws).dup
        cost = run.family.__send__(:total_cost)
        best = run.family
        best_subject = run.subject
        schedule_at = -1
      end

      phase = PHASE_BASELINE
      span_cursor = duplicate_cursor = position = pair_cursor = reorder_cursor = 0
      trivial_cursor = descendant_cursor = character_cursor = shorten_cursor = 0
      paid_cursor = raise_cursor = ordinal = shrinks = stall = 0
      loop do
        kind = Core.shrink_request_kind(
          phase, span_cursor, duplicate_cursor, position, pair_cursor,
          reorder_cursor, trivial_cursor, descendant_cursor, character_cursor,
          shorten_cursor, paid_cursor, raise_cursor, draws.length, spans.length
        )
        break if kind == REQUEST_DONE

        feedback = FEEDBACK_SKIP
        case kind
        when REQUEST_BASELINE
          # The baseline replays a stream that has already failed — the
          # example as found, or a candidate that failed when it was adopted —
          # so one that does not fail now is the property, not the search.
          run = level.call(serialized_draws(draws))
          raise FlakyReplay unless failure?(run.error, origin)

          adopt.call(run)
          feedback = FEEDBACK_ACCEPTED
        when REQUEST_DELETE_SPAN
          span = spans[Core.shrink_request_span(span_cursor, spans.length)]
          candidate = nil
          if span.finish > span.start
            candidate = Core.choice_delete_range(serialized_draws(draws), span.start, span.finish)
          end
          unless candidate.nil?
            run = level.call(candidate)
            if failure?(run.error, origin) && Core.shrink_cost_progress(
              run.family.__send__(:total_cost), cost, draws_simpler?(run.family.__send__(:draws), family_draws)
            )
              adopt.call(run)
              feedback = FEEDBACK_ACCEPTED
            else
              feedback = FEEDBACK_REJECTED
            end
          end
        when REQUEST_DELETE_PAID
          # A deletion the plain pass could not make, paid for by moving the
          # draw after the enclosing structure one step: a list's declared
          # length, an index into it, a parity flag drawn after it.
          at = Core.shrink_request_span(paid_cursor, spans.length)
          start, finish, widened = paid_extent(draws, spans, at)
          step = nil
          unless start.nil?
            follower = paid_follower(spans, at, finish, draws.length)
            step = Core.shrink_delete_paid_variant(ordinal, widened) if !follower.nil? || widened
          end
          unless step.nil?
            trial = draws[0...start] + draws[finish..]
            nudged = nil
            unless step.zero?
              nudged = follower.nil? ? SCHEDULE_MISS : nudge_draw(draws[follower], step)
            end
            if nudged.equal?(SCHEDULE_MISS)
              # This draw cannot take this step; try the next one without
              # running the property.
              feedback = FEEDBACK_REJECTED
            else
              trial[follower - (finish - start)] = nudged unless nudged.nil?
              run = level.call(serialized_draws(trial))
              if failure?(run.error, origin) && Core.shrink_cost_progress(
                run.family.__send__(:total_cost), cost, draws_simpler?(run.family.__send__(:draws), family_draws)
              )
                adopt.call(run)
                feedback = FEEDBACK_ACCEPTED
              else
                feedback = FEEDBACK_REJECTED
              end
            end
          end
        when REQUEST_LOWER
          if position != schedule_at
            schedule_at = position
            schedule_index = draw_index(draws[position])
            schedule_count = schedule_index.nil? ? 0 : Core.shrink_candidate_count(schedule_index)
          end
          candidate = nil
          unless schedule_index.nil?
            index = Core.shrink_candidate_at(schedule_index, ordinal)
            candidate =
              if index.nil?
                # Past the index schedule an integer still has the value-space
                # moves bisection cannot make.
                integer_extra_draw(draws[position], ordinal - schedule_count)
              else
                draw_at_index(draws[position], index)
              end
          end
          unless candidate.nil?
            if candidate.equal?(SCHEDULE_MISS)
              # No legal value here; step the schedule without running.
              feedback = FEEDBACK_REJECTED
            else
              trial = draws.dup
              trial[position] = candidate
              run = level.call(serialized_draws(trial))
              if failure?(run.error, origin) && Core.shrink_cost_progress(
                run.family.__send__(:total_cost), cost, draws_simpler?(run.family.__send__(:draws), family_draws)
              )
                adopt.call(run)
                feedback = FEEDBACK_ACCEPTED
              else
                feedback = FEEDBACK_REJECTED
              end
            end
          end
        when REQUEST_LOWER_DUPLICATES
          # Every draw that currently sits where this one does, lowered as one.
          # Neither member can move alone when the property depends on them
          # being equal: dropping either breaks the failure, so the per-choice
          # pass rejects every candidate and leaves the pair where it was.
          group_key = draw_group_key(draws[duplicate_cursor])
          members =
            if group_key.nil?
              []
            else
              (0...draws.length).select { |at| draw_group_key(draws[at]) == group_key }
            end
          # One position drives each group, so a group of n is tried once and
          # not n times.
          leads = !members.empty? && members.first == duplicate_cursor
          index =
            if leads && Core.shrink_duplicate_worthwhile(members.length, group_key[1])
              Core.shrink_candidate_at(group_key[1], ordinal)
            end
          unless index.nil?
            trial = draws.dup
            missed = false
            members.each do |at|
              candidate = draw_at_index(draws[at], index)
              if candidate.equal?(SCHEDULE_MISS)
                missed = true
                break
              end
              trial[at] = candidate
            end
            if missed
              # No legal value for some member; step the schedule without
              # running the property.
              feedback = FEEDBACK_REJECTED
            else
              run = level.call(serialized_draws(trial))
              if failure?(run.error, origin) && Core.shrink_cost_progress(
                run.family.__send__(:total_cost), cost, draws_simpler?(run.family.__send__(:draws), family_draws)
              )
                adopt.call(run)
                feedback = FEEDBACK_ACCEPTED
              else
                feedback = FEEDBACK_REJECTED
              end
            end
          end
        when REQUEST_LOWER_PAIR
          # Two adjacent integer draws, lowered by one shared amount. This is
          # the difference-preserving move: a property that fails on x-y==5
          # rejects every candidate the per-choice pass offers, because
          # lowering either member alone changes the difference.
          members = [pair_cursor, pair_cursor + 1]
          indexes = members.map { |at| pair_index(draws[at]) }
          base = 0
          index =
            if indexes.none?(&:nil?) && Core.shrink_pair_worthwhile(indexes[0], indexes[1])
              base = Core.shrink_pair_base(indexes[0], indexes[1])
              Core.shrink_candidate_at(base, ordinal)
            end
          unless index.nil?
            trial = draws.dup
            missed = false
            members.zip(indexes).each do |at, current|
              shifted = Core.shrink_pair_candidate(current, base, index)
              if shifted.nil?
                missed = true
                break
              end
              candidate = draw_at_index(draws[at], shifted)
              if candidate.equal?(SCHEDULE_MISS)
                missed = true
                break
              end
              trial[at] = candidate
            end
            if missed
              # No legal value for one member; step the schedule without
              # running the property.
              feedback = FEEDBACK_REJECTED
            else
              run = level.call(serialized_draws(trial))
              if failure?(run.error, origin) && Core.shrink_cost_progress(
                run.family.__send__(:total_cost), cost, draws_simpler?(run.family.__send__(:draws), family_draws)
              )
                adopt.call(run)
                feedback = FEEDBACK_ACCEPTED
              else
                feedback = FEEDBACK_REJECTED
              end
            end
          end
        when REQUEST_TRIVIAL_SPAN
          # A whole span at its simplest values, in one execution.
          span = spans[trivial_cursor]
          unless span.discarded || span.finish <= span.start
            trial, rewritable = trivial_span_candidate(draws, span)
            if Core.shrink_trivial_worthwhile(rewritable)
              run = level.call(serialized_draws(trial))
              if failure?(run.error, origin) && Core.shrink_cost_progress(
                run.family.__send__(:total_cost), cost, draws_simpler?(run.family.__send__(:draws), family_draws)
              )
                adopt.call(run)
                feedback = FEEDBACK_ACCEPTED
              else
                feedback = FEEDBACK_REJECTED
              end
            end
          end
        when REQUEST_DESCENDANT
          # A span replaced by one of its own descendants. Deletion removes a
          # whole subtree; this keeps the subtree and discards the structure
          # wrapped around it, which is the move a nested failure needs when the
          # interesting part is buried rather than beside something.
          inner = descendant_span(spans, descendant_cursor, ordinal)
          candidate =
            unless inner.nil?
              outer = spans[descendant_cursor]
              # Two deletions rather than a new primitive: drop the tail after
              # the descendant, then the head before it. Trailing first, so the
              # leading offsets are still the ones measured above.
              after = Core.choice_delete_range(
                serialized_draws(draws), inner.finish, outer.finish
              )
              Core.choice_delete_range(after, outer.start, inner.start) unless after.nil?
            end
          unless candidate.nil?
            run = level.call(candidate)
            if failure?(run.error, origin) && Core.shrink_cost_progress(
              run.family.__send__(:total_cost), cost, draws_simpler?(run.family.__send__(:draws), family_draws)
            )
              adopt.call(run)
              feedback = FEEDBACK_ACCEPTED
            else
              feedback = FEEDBACK_REJECTED
            end
          end
        when REQUEST_REORDER
          # Two sibling spans trade places. Nothing about the example changes
          # except which order its parts were drawn in, so this reports a
          # canonical arrangement rather than the one generation stumbled on.
          sibling = next_sibling(spans, reorder_cursor)
          candidate =
            unless sibling.nil?
              first = spans[reorder_cursor]
              second = spans[sibling]
              Core.choice_swap_ranges(
                serialized_draws(draws), first.start, first.finish,
                second.start, second.finish
              )
            end
          unless candidate.nil?
            run = level.call(candidate)
            if failure?(run.error, origin) && Core.shrink_cost_progress(
              run.family.__send__(:total_cost), cost, draws_simpler?(run.family.__send__(:draws), family_draws)
            )
              adopt.call(run)
              feedback = FEEDBACK_ACCEPTED
            else
              feedback = FEEDBACK_REJECTED
            end
          end
        when REQUEST_SHORTEN_STRING
          # One character removed from a string draw.
          candidate = shorten_string(draws[shorten_cursor], ordinal)
          unless candidate.nil?
            trial = draws.dup
            trial[shorten_cursor] = candidate
            run = level.call(serialized_draws(trial))
            if failure?(run.error, origin) && Core.shrink_cost_progress(
              run.family.__send__(:total_cost), cost, draws_simpler?(run.family.__send__(:draws), family_draws)
            )
              adopt.call(run)
              feedback = FEEDBACK_ACCEPTED
            else
              feedback = FEEDBACK_REJECTED
            end
          end
        when REQUEST_LOWER_CHARACTERS
          # Every copy of one repeated character in a string draw, lowered
          # together.
          candidate = lower_characters(draws[character_cursor], ordinal)
          unless candidate.nil?
            trial = draws.dup
            trial[character_cursor] = candidate
            run = level.call(serialized_draws(trial))
            if failure?(run.error, origin) && Core.shrink_cost_progress(
              run.family.__send__(:total_cost), cost, draws_simpler?(run.family.__send__(:draws), family_draws)
            )
              adopt.call(run)
              feedback = FEEDBACK_ACCEPTED
            else
              feedback = FEEDBACK_REJECTED
            end
          end
        when REQUEST_RAISE
          # One draw made *less* simple, kept only when the run that comes back
          # is smaller: a gate past its threshold, so the draws behind it are
          # never made. The candidate is larger as written, so the accept rule
          # judges the executed run alone.
          current, largest = raise_bounds(draws[raise_cursor])
          index = current.nil? ? nil : Core.shrink_raise_candidate(current, largest, ordinal)
          unless index.nil?
            candidate = draw_at_index(draws[raise_cursor], index)
            if candidate.equal?(SCHEDULE_MISS)
              # No legal value there; try the next raise without running.
              feedback = FEEDBACK_REJECTED
            else
              trial = draws.dup
              trial[raise_cursor] = candidate
              run = level.call(serialized_draws(trial))
              if failure?(run.error, origin) && Core.shrink_cost_progress(
                run.family.__send__(:total_cost), cost, draws_simpler?(run.family.__send__(:draws), family_draws)
              )
                adopt.call(run)
                feedback = FEEDBACK_ACCEPTED
              else
                feedback = FEEDBACK_REJECTED
              end
            end
          end
        when REQUEST_VERIFY
          run = level.call(serialized_draws(draws))
          raise FlakyReplay unless failure?(run.error, origin)

          verified = [run.error, run.family]
          best = run.family
          best_subject = run.subject
          feedback = FEEDBACK_ACCEPTED
        end

        phase, span_cursor, duplicate_cursor, position, pair_cursor,
        reorder_cursor, trivial_cursor, descendant_cursor, character_cursor,
        shorten_cursor, paid_cursor, raise_cursor, ordinal, shrinks, stall = [
          Core.shrink_next_phase(
            phase, feedback, span_cursor, duplicate_cursor, position, pair_cursor,
            reorder_cursor, trivial_cursor, descendant_cursor, character_cursor,
            shorten_cursor, paid_cursor, raise_cursor, shrinks, stall,
            max_shrinks, max_stall, draws.length, spans.length
          ),
          Core.shrink_next_span_cursor(phase, feedback, span_cursor),
          Core.shrink_next_duplicate_cursor(phase, feedback, duplicate_cursor),
          Core.shrink_next_position(phase, feedback, position),
          Core.shrink_next_pair_cursor(phase, feedback, pair_cursor),
          Core.shrink_next_reorder_cursor(phase, feedback, reorder_cursor),
          Core.shrink_next_trivial_cursor(phase, feedback, trivial_cursor),
          Core.shrink_next_descendant_cursor(phase, feedback, descendant_cursor),
          Core.shrink_next_character_cursor(phase, feedback, character_cursor),
          Core.shrink_next_shorten_cursor(phase, feedback, shorten_cursor),
          Core.shrink_next_paid_cursor(phase, feedback, paid_cursor),
          Core.shrink_next_raise_cursor(phase, feedback, raise_cursor),
          Core.shrink_next_ordinal(phase, feedback, ordinal),
          Core.shrink_next_shrinks(phase, feedback, shrinks),
          Core.shrink_next_stall(stall, feedback)
        ]
      end

      [verified, best, best_subject, accepted, shrinks]
    end

    # Every clone position in a family, outermost first, as the index path from
    # the family's own stream down to the clone.
    #
    # A path rather than a reference because each candidate re-runs the
    # property and so builds a whole new family: the case a path names survives
    # that, a reference into the previous run does not.
    def clone_paths(draws, prefix = [])
      paths = []
      draws.each_with_index do |draw, at|
        next if draw.child.nil?

        path = prefix + [at]
        paths << path
        paths.concat(clone_paths(draw.child.__send__(:draws), path))
      end
      paths
    end

    # Walk a path from a family to the clone stream it names.
    def case_at(family, path)
      at = family
      path.each do |index|
        return nil if index >= at.__send__(:draws).length || at.__send__(:draws)[index].child.nil?

        at = at.__send__(:draws)[index].child
      end
      at
    end

    # Rebuild stream with the clone named by path carrying inner.
    #
    # This is the extract-and-splice the structural core is built around
    # (ir/structure.zir): the bytes inside a clone entry are already a
    # well-formed choice stream, so descending is one extraction per level and
    # the recursion lives here rather than in the IR, which forbids it.
    def splice_at(stream, path, inner)
      offset = Core.choice_offset_at(stream, path.first)
      return nil if offset.nil?

      if path.length > 1
        nested = Core.clone_inner_stream(stream, offset)
        return nil if nested.nil?

        rebuilt = splice_at(nested, path[1..], inner)
        return nil if rebuilt.nil?

        inner = rebuilt
      end
      Core.clone_replace_inner(stream, offset, inner)
    end

    # The level that shrinks the stream inside one clone.
    #
    # Every candidate is spliced into the family's stream at the clone's
    # position and replayed through the whole property, so what is judged is
    # the family's outcome — the child's choices matter only through the
    # failure they still produce. The realized child stream is then read back
    # out of that run.
    def clone_level(property, family, path)
      stream = serialized_draws(family.__send__(:draws))
      lambda do |candidate|
        spliced = splice_at(stream, path, candidate)
        next ShrinkRun.new(family, family, nil) if spliced.nil?

        error, test_case = execute(property, replay: spliced)
        subject = case_at(test_case, path)
        # The candidate changed the shape of the run: whatever it is, it is not
        # this clone's stream any more, so there is nothing to adopt.
        next ShrinkRun.new(test_case, test_case, nil) if subject.nil?

        ShrinkRun.new(test_case, subject, error)
      end
    end

    # Run the whole schedule inside each clone of a family.
    #
    # The flat passes treat a clone entry as one atomic choice — they can
    # delete it or move it, never reach the choices inside it — so a failure
    # that depends on a value drawn from a clone would otherwise be reported
    # exactly as generation found it. Each clone gets its own run of the same
    # compiled driver over its own stream, which is upstream's
    # shrink_clone_streams.
    def shrink_clone_streams(property, family, origin, max_shrinks, max_stall)
      improved = false
      clone_paths(family.__send__(:draws)).each do |path|
        subject = case_at(family, path)
        next if subject.nil? || subject.__send__(:draws).empty?

        _, best, _, accepted = shrink_stream(
          property, clone_level(property, family, path), family, subject, origin,
          max_shrinks: max_shrinks, max_stall: max_stall
        )
        if accepted
          family = best
          improved = true
        end
      end
      [family, improved]
    end

    # Minimize a failing example: the family's own stream first, then the
    # stream inside each of its clones, to a fixpoint.
    #
    # The two alternate because they feed each other — a deletion at the top
    # can expose a clone worth descending into, and a smaller child stream can
    # make a parent candidate legal that was not before. Each accepted
    # candidate is strictly simpler than the one it replaces, so the
    # alternation terminates.
    def shrink(property, initial, origin = nil, max_shrinks: 0, max_stall: 0)
      level = family_level(property)
      loop do
        verified, best, _, accepted, shrinks = shrink_stream(
          property, level, initial, initial, origin,
          max_shrinks: max_shrinks, max_stall: max_stall
        )
        raise "internal error: shrink finished without verifying" if verified.nil?

        family, improved = shrink_clone_streams(
          property, best, origin, max_shrinks, max_stall
        )
        # A sweep that improved the stream goes round again even when no clone
        # did, unless it stopped at its shrink cap: a later pass's accept can
        # make an earlier pass's candidate legal, and one sweep never revisits
        # it. A state machine needs this most, because a continue decision
        # misread after a deletion stops the run, so lowering a rule is often
        # what lets a whole step go.
        again = Core.shrink_sweep_again(accepted, shrinks, max_shrinks)
        return verified unless improved || again

        initial = family
      end
    end
  end

  # Run a property, shrink its first failure, and raise it.
  #
  # Configuration comes from the active profile (see Zizek.register_profile),
  # overridden by any keywords passed here, or from an explicit `settings:`
  # object. Raises Zizek::Failure for a counterexample, and FailedCoverage,
  # TooManyRejections, or FailedHealthCheck for a run that never got one.
  # Use Zizek.run for the same search reported as a value instead.
  def self.check(property = nil, settings: nil, reproduce: nil, **overrides, &block)
    Shell.explore(property || block, Shell.resolve_settings(settings, overrides), reproduce)
    nil
  end

  # The outcome of a run, as a value.
  #
  # `check` raises because a test that quietly ignored a counterexample would
  # be worse than no test. `run` is for the code that wants the verdict
  # instead: a harness collecting blobs, a script comparing shrink quality, a
  # property about a property.
  Result = Struct.new(:outcome, :error, :examples_run, :seed, keyword_init: true) do
    def ok?
      outcome == :ok
    end

    # A counterexample was found. False for a run that failed some other way
    # (coverage, rejections, a health check), which `ok?` also reports.
    def failure?
      outcome == :failure
    end

    def blob
      error.blob if error.respond_to?(:blob)
    end

    def values
      error.respond_to?(:values) ? error.values : []
    end

    def notes
      error.respond_to?(:notes) ? error.notes : []
    end

    def costs
      error.respond_to?(:costs) ? error.costs : {}
    end

    def message
      error&.message
    end

    # Raise whatever this run found, so a `run` call site can escalate without
    # re-deriving which exception class the outcome corresponds to.
    def raise!
      raise error unless ok?

      nil
    end
  end

  # Run a property and report the outcome instead of raising it.
  #
  #   result = Zizek.run(property, examples: 500)
  #   puts result.blob unless result.ok?
  #
  # An invalid replay blob or a bad argument still raises: those are mistakes
  # in the call, not outcomes of the search.
  def self.run(property = nil, settings: nil, reproduce: nil, **overrides, &block)
    summary = Shell.explore(property || block, Shell.resolve_settings(settings, overrides), reproduce)
    Result.new(outcome: :ok, examples_run: summary[:examples_run], seed: summary[:seed])
  rescue Failure => error
    Result.new(outcome: :failure, error: error, examples_run: error.examples_run, seed: error.seed)
  rescue Flaky => error
    Result.new(outcome: :flaky, error: error, examples_run: error.examples_run, seed: error.seed)
  rescue FailedCoverage => error
    Result.new(outcome: :coverage, error: error, examples_run: error.valid)
  rescue TooManyRejections => error
    Result.new(outcome: :exhausted, error: error)
  rescue FailedHealthCheck => error
    Result.new(outcome: :unhealthy, error: error)
  end

  module Shell
    module_function

    # Merge an explicit settings object, per-call overrides, and the active
    # profile into the one Settings the run uses.
    def resolve_settings(settings, overrides)
      base = settings || Zizek.current_settings
      unless base.is_a?(Settings)
        raise ArgumentError, "settings: must be a Zizek::Settings, got #{base.class}"
      end

      base.with(**overrides)
    end

    # Explore, shrink, and adjudicate. Raises on every outcome that is not a
    # clean pass; returns what a clean pass is worth reporting.
    def explore(property, config, reproduce)
      raise ArgumentError, "a property callable or block is required" if property.nil?

      examples = config.examples
      max_rejections = config.max_rejections
      max_shrinks = config.max_shrinks
      max_stall = config.max_stall
      suppress_filter_too_much = config.suppress_filter_too_much
      suppress_data_too_large = config.suppress_data_too_large
      suppress_large_base_example = config.suppress_large_base_example
      suppress_too_slow = config.suppress_too_slow
      required_coverage = config.must_cover

      unless reproduce.nil?
        raw = Core.raw_failure_decode(reproduce.b)
        raise InvalidReplay, "invalid or unsupported reproduce blob" if raw.nil?

        error, replay_case = Shell.execute(property, replay: raw)
        raise InvalidReplay, "reproduced example did not fail" if error.nil?
        raise InvalidReplay, "reproduced example was rejected by an assumption" if error.is_a?(AssumptionRejected)
        raise error if error.is_a?(ReplayOverrun) || error.is_a?(InvalidReplay)

        raise Failure.new(
          blob: reproduce, property_cause: error, examples_run: 1, rejections: 0,
          notes: replay_case.__send__(:notes), values: replay_case.__send__(:drawn), puns: replay_case.__send__(:puns),
          key_misses: replay_case.__send__(:key_misses), costs: replay_case.__send__(:costs)
        )
      end

      seed = config.__send__(:effective_seed, property)
      database = Database.__send__(:resolve, config.database)
      database_key = config.database_key
      # Deliberately local to Ruby: where a property was written says nothing
      # to the Python or Go suite testing the same behaviour, and a key that
      # pretended otherwise would file a counterexample where the other
      # language will never look for it. Set `database_key:` to share one.
      database_key ||= Settings.__send__(:property_identity, property) unless database.nil?
    coverage = []
    coverage_index = {}
    required_coverage.each do |required|
      permille = (required.percent * 10).to_i
      if coverage_index.key?(required.label)
        at = coverage_index[required.label]
        coverage[at].permille = [coverage[at].permille, permille].max
        next
      end
      coverage_index[required.label] = coverage.length
      coverage << Shell::CoverageCounter.new(required.label, permille, 0)
    end
    rng = Random.new(seed)
    valid = 0
    attempts = 0
    # Database replays are attempts but not generation. The schedule is told
    # generation's own count, so a stale entry cannot take the all-simplest
    # probe's place as the first request.
    replays = 0
    rejections = 0
    overruns = 0
    generation_us = 0
    pending_mutations = []
    # Consecutive executed mutation requests; the schedule caps it at one
    # brood so fresh random generation keeps its share of the run.
    mutation_streak = 0
    choice_tree = Shell::ChoiceTree.new
    # Per-label best score and the stream that produced it, for the targeting
    # hill climber. The schedule, budgets, record and accept rules, stepping,
    # and the step-size search are all compiled (ir/targeting.zir); this loop
    # holds the maps and runs the trials.
    targeting_best = {}
    targeting_step = Core.targeting_schedule_step(examples)
    targeting_next_at = targeting_step
    targeting_trial_budget = Core.targeting_trial_budget(examples)

    # Fold a valid example's targeting observations into the per-label bests.
    record_targets = lambda do |test_case|
      test_case.__send__(:targets).each do |label, score|
        entry = targeting_best[label]
        if Core.targeting_record(!entry.nil?, entry.nil? ? 0.0 : entry[0], score)
          targeting_best[label] = [score, test_case.__send__(:serialized)]
        end
      end
    end

    # Shrink a failing case, store what it shrank to, and build the failure.
    # A replay during the search that stops failing is reported as Flaky,
    # carrying the failure as found rather than a shrunk one that cannot be
    # trusted; nothing is stored or collected for it.
    counterexample = lambda do |test_case, error, replaced|
      begin
        shrunk_error, shrunk_case = Shell.shrink(
          property, test_case, Shell.interesting_origin(error),
          max_shrinks: max_shrinks, max_stall: max_stall
        )
      rescue FlakyReplay
        next Flaky.new(
          blob: Core.raw_failure_encode(test_case.__send__(:serialized)), property_cause: error,
          examples_run: attempts, rejections: rejections, seed: seed
        )
      end
      stream = shrunk_case.__send__(:serialized)
      unless database.nil?
        database.save(database_key, stream)
        # The entry that reproduced is superseded by whatever it shrank to, so
        # it goes; an entry that shrank to itself is already stored.
        database.delete(database_key, replaced) if !replaced.nil? && replaced != stream
      end
      Failure.new(
        blob: Core.raw_failure_encode(stream), property_cause: shrunk_error,
        examples_run: attempts, rejections: rejections,
        notes: shrunk_case.__send__(:notes), values: shrunk_case.__send__(:drawn), seed: seed,
        puns: shrunk_case.__send__(:puns), key_misses: shrunk_case.__send__(:key_misses),
        costs: shrunk_case.__send__(:costs)
      )
    end

    # One targeting trial: replay a stepped stream with fresh-RNG extension —
    # the execution mode mutation probes already use — counting it as an
    # ordinary attempt. Answers nil when the firing's budget is spent,
    # otherwise [error, test_case, outcome].
    targeting_trial = lambda do |stream|
      if valid >= examples || attempts >= targeting_trial_budget
        nil
      else
        attempts += 1
        error, trial_case = Shell.execute(property, rng: rng, replay: stream)
        choice_tree.insert(trial_case.__send__(:serialized))
        if error.nil?
          valid += 1
          record_targets.call(trial_case)
        end
        [error, trial_case, Shell.classify(error)]
      end
    end

    # Hill-climb one label's best-known stream: walk its realized draws from
    # the end backwards, stepping each climbable draw through the compiled
    # step-size search, in the +k direction and then -k. Answers
    # [improvements, interesting], where interesting is a failing trial the
    # ordinary counterexample path takes over. Mirrors
    # hegel-c/src/native/targeting.rs::hill_climb.
    targeting_climb = lambda do |label, allowance|
      trial = targeting_trial.call(targeting_best[label][1])
      return [0, nil] if trial.nil?

      error, current_case, outcome = trial
      return [0, [error, current_case]] if outcome == Shell::OUTCOME_INTERESTING
      return [0, nil] unless error.nil?

      current_score = current_case.__send__(:targets).fetch(label, -Float::INFINITY)
      improvements = 0
      interesting = nil
      examined = {}
      at = current_case.__send__(:draws).length - 1
      previous_length = current_case.__send__(:draws).length
      while at >= 0 && improvements <= allowance && interesting.nil?
        if current_case.__send__(:draws).length != previous_length
          at = current_case.__send__(:draws).length - 1
          previous_length = current_case.__send__(:draws).length
          next
        end
        if examined[at]
          at -= 1
          next
        end
        examined[at] = true
        draw = current_case.__send__(:draws)[at]
        if Shell.climbable_draw?(draw)
          length_before = current_case.__send__(:draws).length
          [1, -1].each do |direction|
            break unless interesting.nil?
            # The -k direction only makes sense while the draw survived the
            # +k climb at the same index with the stream length unchanged.
            if direction == -1 &&
               (at >= current_case.__send__(:draws).length || current_case.__send__(:draws).length != length_before)
              break
            end

            mode = 0
            a = 1
            b = 0
            loop do
              # A committed improvement may have shortened the stream below
              # this index; the outer walk restarts from the new end.
              break if at >= current_case.__send__(:draws).length

              probe = Core.find_integer_probe(mode, a, b)
              break if probe.nil?

              committed = false
              if probe <= Core.targeting_step_cap
                stepped = Shell.step_draw(current_case.__send__(:draws)[at], direction * probe)
                unless stepped.nil?
                  draws = current_case.__send__(:draws).dup
                  draws[at] = stepped
                  trial = targeting_trial.call(Shell.serialized_draws(draws))
                  break if trial.nil?

                  trial_error, trial_case, trial_outcome = trial
                  if trial_outcome == Shell::OUTCOME_INTERESTING
                    interesting = [trial_error, trial_case]
                    break
                  end
                  if trial_error.nil?
                    trial_score = trial_case.__send__(:targets).fetch(label, -Float::INFINITY)
                    accept = Core.targeting_accept(
                      trial_score, current_score,
                      Shell.flat_draw_count(trial_case.__send__(:draws)),
                      Shell.flat_draw_count(current_case.__send__(:draws))
                    )
                    unless accept.zero?
                      current_case = trial_case
                      current_score = trial_score
                      improvements += 1 if accept == 2
                      committed = true
                    end
                  end
                end
              end
              next_mode = Core.find_integer_next_mode(mode, a, b, committed)
              next_a = Core.find_integer_next_a(mode, a, b, committed)
              next_b = Core.find_integer_next_b(mode, a, b, committed)
              mode = next_mode
              a = next_a
              b = next_b
            end
          end
        end
        at -= 1
      end
      [improvements, interesting]
    end

    # Climb every label until a full round improves nothing or the budget is
    # spent. Mirrors targeting.rs::optimise_targets, with the improvement
    # allowance doubling each round.
    optimise_targets = lambda do
      round = 0
      loop do
        calls_before = attempts
        any_improvements = false
        allowance = Core.targeting_improvement_allowance(round)
        targeting_best.keys.sort.each do |label|
          improvements, interesting = targeting_climb.call(label, allowance)
          return interesting unless interesting.nil?

          any_improvements = true if improvements.positive?
        end
        round += 1
        return nil if !any_improvements || attempts == calls_before
      end
    end

    # Reuse before generate: replay what earlier runs stored under this name,
    # simplest first. An entry that still fails is the answer; one that does
    # not is a bug that was fixed, and collecting it now keeps every future run
    # from paying for it. Replays are counted as attempts but not as valid
    # examples, so a stored corpus never eats the exploration budget, and they
    # feed neither the coverage verdict nor the health checks — both are
    # statements about what this run explored.
    unless database.nil?
      database.fetch(database_key).sort_by { |entry| Database.__send__(:shortlex, entry) }.each do |entry|
        unless Core.choice_stream_validate(entry)
          database.delete(database_key, entry)
          next
        end
        attempts += 1
        replays += 1
        error, test_case = Shell.execute(property, replay: entry)
        if Shell.classify(error) != Shell::OUTCOME_INTERESTING
          database.delete(database_key, entry)
          next
        end
        raise counterexample.call(test_case, error, entry)
      end
    end

    while Core.generation_should_continue(valid, examples)
      request = Core.generation_request_kind(attempts - replays, pending_mutations.length, mutation_streak)
      simplest_probe = request == 1
      mutation_probe = request == 2
      mutation = mutation_probe ? pending_mutations.shift : nil
      novelty = Core.generation_novelty_action(request, mutation_probe && choice_tree.include?(mutation))
      next if novelty.zero?
      choice_tree.insert(mutation) if novelty == 2
      attempts += 1
      mutation_streak = mutation_probe ? mutation_streak + 1 : 0
      error, test_case = Shell.execute(
        property,
        rng: simplest_probe ? nil : rng,
        replay: mutation,
        simplest: simplest_probe
      )
      choice_tree.insert(test_case.__send__(:serialized))
      generation_us = [((1 << 64) - 1), generation_us + test_case.__send__(:generation_us)].min
      outcome = Shell.classify(error)
      if Core.health_large_base_example(
        error.is_a?(ChoiceOverrun),
        outcome,
        test_case.__send__(:draws).length,
        suppress_large_base_example
      )
        raise FailedHealthCheck.new(
          :large_base_example,
          "large_base_example: the simplest natural input is too large"
        )
      end
      health_valid = valid + (error.nil? ? 1 : 0)
      if outcome != Shell::OUTCOME_INTERESTING &&
         Core.health_too_slow(generation_us, health_valid, suppress_too_slow)
        raise FailedHealthCheck.new(
          :too_slow,
          "too_slow: input generation exceeded one cumulative second " \
          "while only #{health_valid} valid inputs were generated"
        )
      end
      if error.nil?
        valid += 1
        # An example that reached a label the run has barely covered is on the
        # frontier, so its mutation proposals jump the queue ahead of ones bred
        # from the common path, and may be bred at all when the base rule
        # declines.
        held_rare = false
        test_case.__send__(:coverage_order).each do |label|
          unless coverage_index.key?(label)
            coverage_index[label] = coverage.length
            coverage << Shell::CoverageCounter.new(label, 0, 0)
          end
          counter = coverage[coverage_index[label]]
          counter.permille = [counter.permille, test_case.__send__(:coverage_permille)[label]].max
          next unless test_case.__send__(:coverage_held)[label]

          counter.observed += 1
          held_rare = true if Core.generation_label_rare(counter.observed, valid, counter.permille)
        end
        admission = Core.generation_mutation_admission(
          request, valid, pending_mutations.length, held_rare
        )
        unless admission.zero?
          proposals = Shell.span_mutation_candidates(test_case.__send__(:draws), test_case.__send__(:spans), rng)
          if admission == 2
            pending_mutations.unshift(*proposals)
          else
            pending_mutations.concat(proposals)
          end
        end
        # Targeting: fold this example's observations in, and fire the hill
        # climber when the schedule says so. A failing trial is a
        # counterexample like any other.
        record_targets.call(test_case)
        if !targeting_best.empty? && Core.targeting_should_fire(valid, targeting_next_at)
          targeting_next_at = Core.targeting_next_threshold(targeting_next_at, targeting_step)
          found = optimise_targets.call
          raise counterexample.call(found[1], found[0], nil) unless found.nil?
        end
        next
      end
      if error.is_a?(AssumptionRejected)
        rejections += 1
        rejection_limit = Core.generation_rejection_limit(max_rejections, valid)
        if rejections + overruns > rejection_limit
          raise TooManyRejections.new(rejections + overruns, rejection_limit)
        end
        if Core.health_filter_too_much(rejections, valid, suppress_filter_too_much)
          raise FailedHealthCheck.new(
            :filter_too_much,
            "filter_too_much: #{rejections} inputs were rejected by assumptions " \
            "while only #{valid} valid inputs were generated"
          )
        end
        next
      end
      if error.is_a?(ChoiceOverrun)
        overruns += 1
        rejection_limit = Core.generation_rejection_limit(max_rejections, valid)
        if rejections + overruns > rejection_limit
          raise TooManyRejections.new(rejections + overruns, rejection_limit)
        end
        if Core.health_data_too_large(overruns, valid, suppress_data_too_large)
          raise FailedHealthCheck.new(
            :data_too_large,
            "data_too_large: #{overruns} inputs exceeded the choice budget " \
            "while only #{valid} valid inputs were generated"
          )
        end
        next
      end
      raise error if error.is_a?(InvalidReplay)

      raise counterexample.call(test_case, error, nil)
    end
    # The coverage verdict runs only on a run that completed fully valid: a
    # counterexample or an aborted run reports that instead, and a verdict
    # about a truncated run would be noise. The accept rule is compiled
    # (ir/lifecycle.zir @coverage_failed) so every shell agrees on it.
    coverage.each do |counter|
      next unless Core.coverage_failed(counter.observed, valid, counter.permille)

      raise FailedCoverage.new(counter.label, counter.observed, valid, counter.permille / 10.0)
    end
    { examples_run: attempts, valid: valid, rejections: rejections, seed: seed }
    end
  end

  private_class_method :key_encode
  private_constant :Core, :Shell, :Draw, :ChoiceSpan, :UNICODE
end
