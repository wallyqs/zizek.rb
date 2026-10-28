# frozen_string_literal: true

require "set"

module Zizek
  module Generators
    # Transformations every generator carries. Neither records a choice of its
    # own, so composing them leaves the reproduce blob byte-compatible with the
    # other packages.
    module Combinators
      # Apply a block to each drawn value.
      def map(&transform)
        MappedGenerator.new(self, transform)
      end

      # Keep only values satisfying a block. Draws are retried a few times
      # before the example is rejected, matching how the engine treats a
      # filtered generator: a rejection discards the example rather than
      # failing the property.
      def filter(&predicate)
        FilteredGenerator.new(self, predicate)
      end

      # Build the next generator from each drawn value — monadic bind.
      #
      #   Generators.integers(0..3).flat_map do |length|
      #     Generators.lists(Generators.booleans, min: length, max: length)
      #   end
      #
      # Both draws share one `flat_map` span, so the shrinker can delete or
      # simplify the whole unit together: shrinking the source value changes
      # which inner generator runs, and the inner draws replay or pun by the
      # ordinary prefix rules.
      def flat_map(&transform)
        FlatMappedGenerator.new(self, transform)
      end

      # Either generator, shrinking towards the left one.
      #
      #   Generators.integers(max: 0) | Generators.text(max: 4)
      #
      # Chains flatten: `a | b | c` is the three-way `one_of(a, b, c)`, not a
      # two-way choice nested inside another, so the shrinker sees one index
      # to lower rather than two.
      def |(other)
        Generators.one_of(*Generators.__send__(:one_of_parts, self), *Generators.__send__(:one_of_parts, other))
      end

      # One value, for a REPL or a docstring.
      #
      # This is not a generator you can shrink or replay — it runs no property
      # and records nothing. It exists so `Generators.text(max: 5).example`
      # answers "what does this actually produce?" without writing a test.
      def example(seed: nil)
        rng = Random.new(seed.nil? ? Random.new_seed : seed)
        attempts = 0
        begin
          attempts += 1
          TestCase.new(rng: rng).draw(self)
        rescue AssumptionRejected, ChoiceOverrun
          retry if attempts < 32
          raise Unsatisfiable, "no example after #{attempts} attempts; the filter may be too strict"
        end
      end
    end

    class MappedGenerator
      include Combinators

      def initialize(source, transform)
        @source = source
        @transform = transform
      end

      def do_draw(test_case)
        @transform.call(@source.do_draw(test_case))
      end
    end

    class FlatMappedGenerator
      include Combinators

      def initialize(source, transform)
        @source = source
        @transform = transform
      end

      def do_draw(test_case)
        test_case.start_span("flat_map")
        value = @source.do_draw(test_case)
        result = Generators.__send__(:coerce, @transform.call(value)).do_draw(test_case)
        test_case.stop_span
        result
      end
    end

    class FilteredGenerator
      include Combinators

      def initialize(source, predicate)
        @source = source
        @predicate = predicate
      end

      def do_draw(test_case)
        # The attempt budget is the same one a unique collection spends per
        # element, so it comes from ir/many.zir rather than a constant here.
        attempts = 0
        while Core.filter_retry_allowed(attempts)
          value = @source.do_draw(test_case)
          attempts += 1
          return value if @predicate.call(value)
        end
        test_case.assume(false)
      end
    end

    # Always the same value, recording no choice at all.
    class JustGenerator
      include Combinators

      def initialize(value)
        @value = value
      end

      def do_draw(_test_case)
        @value
      end
    end

    class BooleanGenerator
      include Combinators

      def do_draw(test_case)
        test_case.boolean
      end
    end

    class WeightedBooleanGenerator
      include Combinators

      attr_reader :probability
      private :probability

      def initialize(probability)
        @probability = probability
      end

      def do_draw(test_case)
        test_case.weighted(@probability)
      end
    end

    class BytesGenerator
      include Combinators

      attr_reader :minimum, :maximum
      private :minimum, :maximum

      def initialize(minimum = 0, maximum = 16)
        @minimum = minimum
        @maximum = maximum
      end

      def min_size(value)
        self.class.new(value, maximum)
      end

      def max_size(value)
        self.class.new(minimum, value)
      end

      def do_draw(test_case)
        test_case.bytes(minimum, maximum)
      end
    end

    # One of a fixed sequence, shrinking towards the first element. The index
    # is a real integer choice, so it shrinks and replays like any other.
    class SampledGenerator
      include Combinators

      def initialize(values)
        @values = values
      end

      def do_draw(test_case)
        @values[test_case.integer(0, @values.length - 1)]
      end
    end

    # One of several generators, shrinking towards the first.
    class OneOfGenerator
      include Combinators

      attr_reader :choices
      private :choices

      def initialize(choices)
        @choices = choices
      end

      def do_draw(test_case)
        @choices[test_case.integer(0, @choices.length - 1)].do_draw(test_case)
      end
    end

    # Each generator in order, collected into an array.
    class TupleGenerator
      include Combinators

      def initialize(parts)
        @parts = parts
      end

      def do_draw(test_case)
        @parts.map { |part| part.do_draw(test_case) }
      end
    end

    # A generator assembled by a block that draws as it goes.
    class CompositeGenerator
      include Combinators

      def initialize(build)
        @build = build
      end

      # The block is handed the test case itself rather than a bare draw
      # lambda, so a composite can `assume`, `note`, and name its draws the
      # same way a property can.
      def do_draw(test_case)
        @build.call(test_case)
      end
    end

    # A generator that builds an object out of drawn parts.
    class BuiltGenerator
      include Combinators

      def initialize(builder, parts, keyword_parts)
        @builder = builder
        @parts = parts
        @keyword_parts = keyword_parts
      end

      def do_draw(test_case)
        args = @parts.map { |part| part.do_draw(test_case) }
        if @keyword_parts.empty?
          @builder.call(*args)
        else
          kwargs = @keyword_parts.transform_values { |part| part.do_draw(test_case) }
          @builder.call(*args, **kwargs)
        end
      end
    end
  end
end

module Zizek
  module Generators
    class IntegerGenerator
      include Combinators

      attr_reader :minimum, :maximum, :target
      private :minimum, :maximum, :target

      def initialize(minimum = -(1 << 63), maximum = (1 << 63) - 1, target = nil)
        @minimum = minimum
        @maximum = maximum
        @target = target
      end

      def min_value(value)
        self.class.new(value, maximum, target)
      end

      def max_value(value)
        self.class.new(minimum, value, target)
      end

      def shrink_towards(value)
        self.class.new(minimum, maximum, value)
      end

      def do_draw(test_case)
        # An explicit target is passed through unclamped: integer_simplest
        # already clamps it to the nearer bound. The default is compiled so the
        # shells cannot drift on it.
        destination = target
        destination = Core.integer_default_shrink_target(minimum, maximum) if destination.nil?
        test_case.integer(minimum, maximum, shrink_towards: destination)
      end
    end

    # Text over an alphabet, by default every Unicode scalar value. Values
    # shrink shortlex over the alphabet's shrink order — shorter first, then
    # towards "0", the digits, and the uppercase letters — so a minimal
    # failing string is one a reader can retype.
    class TextGenerator
      include Combinators

      attr_reader :minimum, :maximum, :characters
      private :minimum, :maximum, :characters

      def initialize(minimum = 0, maximum = nil, characters = nil)
        @minimum = minimum
        @maximum = maximum
        @characters = characters
      end

      def min_size(value)
        self.class.new(value, maximum, characters)
      end

      def max_size(value)
        self.class.new(minimum, value, characters)
      end

      # Restrict the characters drawn. Takes either the characters themselves
      # or an interval set from Zizek.alphabet_range.
      def alphabet(value)
        value = Zizek.alphabet(value) if value.is_a?(String) && value.encoding != Encoding::BINARY
        self.class.new(minimum, maximum, value)
      end

      def do_draw(test_case)
        limit = maximum.nil? ? Core.text_widened_max(minimum) : maximum
        test_case.string(minimum, limit, alphabet: characters)
      end
    end

    class FloatGenerator
      include Combinators

      attr_reader :minimum, :maximum, :allow_nan_values, :allow_infinity_values,
                  :smallest_nonzero
      private :minimum, :maximum, :allow_nan_values, :allow_infinity_values, :smallest_nonzero

      def initialize(
        minimum = -Float::INFINITY,
        maximum = Float::INFINITY,
        allow_nan_values = false,
        allow_infinity_values = false,
        smallest_nonzero = 0.0
      )
        @minimum = minimum
        @maximum = maximum
        @allow_nan_values = allow_nan_values
        @allow_infinity_values = allow_infinity_values
        @smallest_nonzero = smallest_nonzero
      end

      def copy(**changes)
        self.class.new(
          changes.fetch(:minimum, minimum),
          changes.fetch(:maximum, maximum),
          changes.fetch(:allow_nan_values, allow_nan_values),
          changes.fetch(:allow_infinity_values, allow_infinity_values),
          changes.fetch(:smallest_nonzero, smallest_nonzero)
        )
      end

      private :copy

      def min_value(value)
        copy(minimum: value)
      end

      def max_value(value)
        copy(maximum: value)
      end

      def allow_nan(value = true)
        copy(allow_nan_values: value)
      end

      def allow_infinity(value = true)
        copy(allow_infinity_values: value)
      end

      def smallest_nonzero_magnitude(value)
        copy(smallest_nonzero: value)
      end

      def do_draw(test_case)
        test_case.float(
          minimum,
          maximum,
          allow_nan: allow_nan_values,
          allow_infinity: allow_infinity_values,
          smallest_nonzero_magnitude: smallest_nonzero
        )
      end
    end

    # A variable-length list of values drawn from one element generator.
    class ListGenerator
      include Combinators

      attr_reader :element, :minimum, :maximum
      private :element, :minimum, :maximum

      def initialize(element, minimum = 0, maximum = nil)
        @element = element
        @minimum = minimum
        @maximum = maximum
      end

      def min_size(value)
        self.class.new(element, value, maximum)
      end

      def max_size(value)
        self.class.new(element, minimum, value)
      end

      def do_draw(test_case)
        test_case.__send__(:collect, element, minimum, maximum, "list.element")
      end
    end

    # A variable-length collection whose elements are distinct under a key.
    class UniqueListGenerator
      include Combinators

      attr_reader :element, :key, :minimum, :maximum, :label
      private :element, :key, :minimum, :maximum, :label

      def initialize(element, key = nil, minimum = 0, maximum = nil, label = "list.element")
        @element = element
        @key = key
        @minimum = minimum
        @maximum = maximum
        @label = label
      end

      def min_size(value)
        self.class.new(element, key, value, maximum, label)
      end

      def max_size(value)
        self.class.new(element, key, minimum, value, label)
      end

      def unique_by(&block)
        self.class.new(element, block, minimum, maximum, label)
      end

      def do_draw(test_case)
        test_case.__send__(:collect_unique, element, key, minimum, maximum, label)
      end
    end

    # A set of distinct values, materialized as a Ruby Set.
    class SetGenerator < UniqueListGenerator
      def initialize(element, minimum = 0, maximum = nil)
        super(element, nil, minimum, maximum, "set.element")
      end

      def min_size(value)
        self.class.new(element, value, maximum)
      end

      def max_size(value)
        self.class.new(element, minimum, value)
      end

      def do_draw(test_case)
        Set.new(super)
      end
    end

    # One key/value pair, drawn as a unit so that deleting its span deletes both
    # halves together.
    class PairGenerator
      include Combinators

      attr_reader :keys, :values
      private :keys, :values

      def initialize(keys, values)
        @keys = keys
        @values = values
      end

      def do_draw(test_case)
        [test_case.draw(keys), test_case.draw(values)]
      end
    end

    # A Hash whose keys are distinct.
    class HashGenerator
      include Combinators

      attr_reader :keys, :values, :minimum, :maximum
      private :keys, :values, :minimum, :maximum

      def initialize(keys, values, minimum = 0, maximum = nil)
        @keys = keys
        @values = values
        @minimum = minimum
        @maximum = maximum
      end

      def min_size(value)
        self.class.new(keys, values, value, maximum)
      end

      def max_size(value)
        self.class.new(keys, values, minimum, value)
      end

      def do_draw(test_case)
        entries = test_case.__send__(:collect_unique,
          PairGenerator.new(keys, values), ->(entry) { entry[0] }, minimum, maximum, "hash.entry"
        )
        entries.to_h
      end
    end

    class RecursiveLeafBudget < StandardError; end

    class RecursiveState
      attr_accessor :attempt, :leaves, :start_price, :closed_children,
                    :closed_branches, :open_branches, :reprices
      attr_reader :max_depth, :max_leaves, :target

      def initialize(max_depth, max_leaves, target)
        @max_depth = max_depth
        @max_leaves = max_leaves
        @target = target
        @attempt = @leaves = @closed_children = @closed_branches = @reprices = 0
        @start_price = 0.0
        @open_branches = []
      end

      def observe_decision(depth)
        while !open_branches.empty? && open_branches.last[0] >= depth
          _, children = open_branches.pop
          self.closed_children += children
          self.closed_branches += 1
        end
        open_branches.last[1] += 1 if depth.positive? && !open_branches.empty?
      end

      def close_branches
        until open_branches.empty?
          _, children = open_branches.pop
          self.closed_children += children
          self.closed_branches += 1
        end
      end
    end

    class RecursiveSubtreeGenerator
      include Combinators

      def initialize(owner, state, depth)
        @owner = owner
        @state = state
        @depth = depth
      end

      def do_draw(test_case)
        test_case.start_span("recursive")
        @state.observe_decision(@depth)
        probability = Core.recursive_decision_probability(
          @state.max_depth, @depth, @state.target, @state.attempt,
          @state.closed_children, @state.closed_branches
        )
        branch = if @depth >= @state.max_depth
                   test_case.__send__(:forced_boolean, false)
                 else
                   test_case.weighted(probability)
                 end
        value = if branch
                  @state.open_branches << [@depth, 0]
                  @owner.__send__(:branch).call(
                    self.class.new(@owner, @state, @depth + 1)
                  ).do_draw(test_case)
                else
                  raise RecursiveLeafBudget if @state.leaves >= @state.max_leaves

                  @state.leaves += 1
                  @owner.__send__(:leaf).do_draw(test_case)
                end
        test_case.stop_span unless @depth.zero?
        value
      end
    end

    class RecursiveGenerator
      include Combinators

      attr_reader :leaf, :branch, :max_depth_limit, :max_leaves_limit
      private :leaf, :branch, :max_depth_limit, :max_leaves_limit

      def initialize(leaf, branch, max_depth = 32, max_leaves = 100)
        @leaf = leaf
        @branch = branch
        @max_depth_limit = max_depth
        @max_leaves_limit = max_leaves
      end

      def max_depth(value)
        raise ArgumentError, "max_depth must be nonnegative" if value.negative?

        self.class.new(leaf, branch, value, max_leaves_limit)
      end

      def max_leaves(value)
        if value.negative? || value > (1 << 63) - 1
          raise ArgumentError, "max_leaves must be in [0, 2^63 - 1]"
        end

        self.class.new(leaf, branch, max_depth_limit, value)
      end

      def do_draw(test_case)
        base_depth = test_case.__send__(:open_span_depth)
        target = 1
        if Core.recursive_target_drawn(max_leaves_limit) &&
           test_case.weighted(Core.recursive_large_target_probability)
          target = test_case.integer(2, max_leaves_limit, _uniform: true)
        end
        state = RecursiveState.new(max_depth_limit, max_leaves_limit, target)
        state.start_price = Core.recursive_priced_probability(0, 0, 0, target)
        loop do
          begin
            value = RecursiveSubtreeGenerator.new(self, state, 0).do_draw(test_case)
          rescue RecursiveLeafBudget
            test_case.__send__(:reset_open_spans_to, base_depth)
            state.open_branches.clear
            state.leaves = 0
            state.attempt += 1
            test_case.assume(false) unless Core.recursive_retry_allowed(state.attempt)
            state.start_price = Core.recursive_priced_probability(
              state.closed_children, state.closed_branches, state.attempt, state.target
            )
            next
          end
          state.close_branches
          unless Core.recursive_finish_mispriced(
            state.max_depth, state.target, state.attempt, state.leaves,
            state.closed_children, state.closed_branches, state.start_price, state.reprices
          )
            test_case.stop_span
            return value
          end
          test_case.__send__(:reset_open_spans_to, base_depth)
          state.leaves = 0
          state.reprices += 1
          state.start_price = Core.recursive_priced_probability(
            state.closed_children, state.closed_branches, state.attempt, state.target
          )
        end
      end
    end

    module_function

    # Whole numbers, biased towards interesting boundaries and shrinking
    # towards `shrink_towards` (zero, clamped into range, by default).
    #
    #   Generators.integers(min: 0, max: 100)
    #   Generators.integers(min: -100, max: 100, shrink_towards: 10)
    #   Generators.integers(0..100)               # the same, as a range
    #
    # The fluent form stays available for building a generator in stages, and
    # means the same thing: `integers(min: 0, max: 100)` is
    # `integers.min_value(0).max_value(100)`.
    def integers(range = nil, min: nil, max: nil, shrink_towards: nil)
      min, max = range_bounds(range, min, max, :integers, exclusive_end: true)
      generator = IntegerGenerator.new
      generator = generator.min_value(min) unless min.nil?
      generator = generator.max_value(max) unless max.nil?
      generator = generator.shrink_towards(shrink_towards) unless shrink_towards.nil?
      generator
    end

    # Interpret the optional range argument the bounded factories accept.
    #
    # A range and explicit bounds are mutually exclusive rather than merged:
    # `integers(0..10, min: 5)` reads as if one of them wins, and guessing
    # which would be worse than refusing.
    def range_bounds(range, min, max, name, exclusive_end:)
      return [min, max] if range.nil?
      unless min.nil? && max.nil?
        raise ArgumentError, "#{name} takes either a range or min:/max:, not both"
      end
      raise ArgumentError, "#{name} takes a Range, got #{range.class}" unless range.is_a?(Range)

      high = range.end
      if range.exclude_end? && !high.nil?
        unless exclusive_end
          raise ArgumentError, "#{name} needs an inclusive range; #{range.inspect} excludes its end"
        end

        high -= 1
      end
      [range.begin, high]
    end
    private_class_method :range_bounds

    # Generate a list whose elements each occupy a deletable span.
    #
    # Unlike the scalar generators this one has structure the shrinker can
    # reduce: it deletes whole elements before it simplifies the values inside
    # them, so a failing list minimizes towards the shortest list that still
    # fails rather than towards small elements in a long list.
    def lists(element, min: 0, max: nil, unique: false, unique_by: nil)
      return ListGenerator.new(element, min, max) unless unique || unique_by

      UniqueListGenerator.new(element, unique_by, min, max)
    end

    # Generate a Set of distinct values.
    #
    # A set is a unique list the shrinker can still delete elements from: each
    # element keeps its own span, and a candidate that duplicates an earlier one
    # is discarded rather than failing the example.
    def sets(element, min: 0, max: nil)
      SetGenerator.new(element, min, max)
    end

    # Generate a Hash with distinct keys.
    #
    # Uniqueness is judged on the key alone, so the value generator is free to
    # repeat.
    def hashes(keys, values, min: 0, max: nil)
      HashGenerator.new(keys, values, min, max)
    end

    # Generate text over an alphabet, by default every Unicode scalar value.
    def text(min: 0, max: nil, alphabet: nil)
      alphabet = Zizek.alphabet(alphabet) if alphabet.is_a?(String) && alphabet.encoding != Encoding::BINARY
      TextGenerator.new(min, max, alphabet)
    end

    # IEEE-754 doubles, biased towards interesting bit patterns.
    #
    #   Generators.floats(min: 0.0, max: 1.0)
    #   Generators.floats(allow_nan: true, allow_infinity: true)
    #   Generators.floats(0.0..1.0)
    #
    # NaN and the infinities are excluded by default: a property that has an
    # opinion about them should say so.
    def floats(range = nil, min: nil, max: nil, allow_nan: nil, allow_infinity: nil,
               smallest_nonzero_magnitude: nil)
      min, max = range_bounds(range, min, max, :floats, exclusive_end: false)
      generator = FloatGenerator.new
      generator = generator.min_value(min) unless min.nil?
      generator = generator.max_value(max) unless max.nil?
      generator = generator.allow_nan(allow_nan) unless allow_nan.nil?
      generator = generator.allow_infinity(allow_infinity) unless allow_infinity.nil?
      unless smallest_nonzero_magnitude.nil?
        generator = generator.smallest_nonzero_magnitude(smallest_nonzero_magnitude)
      end
      generator
    end

    # Generate booleans, shrinking towards false.
    def booleans
      BooleanGenerator.new
    end

    # Generate booleans that are true with the given probability. Recorded as
    # an ordinary boolean choice: the weight biases generation only, so a
    # blob replays the same whatever probability produced it.
    def weighted_booleans(probability)
      unless probability.is_a?(Numeric) && probability.finite? && probability >= 0.0 && probability <= 1.0
        raise ArgumentError, "weighted_booleans requires a probability in [0.0, 1.0]"
      end

      WeightedBooleanGenerator.new(probability)
    end

    # Generate byte strings, shrinking towards shorter and lower values.
    def binary(min: 0, max: 16)
      BytesGenerator.new(min, max)
    end

    # Always produce one value, recording no choice.
    def just(value)
      JustGenerator.new(value)
    end

    # Always produce nil.
    def none
      JustGenerator.new(nil)
    end

    # Pick one of a fixed sequence, shrinking towards the first element.
    def sampled_from(values)
      values = values.to_a
      raise ArgumentError, "sampled_from requires at least one value" if values.empty?

      SampledGenerator.new(values)
    end

    # Draw from one of several generators, shrinking towards the first.
    def one_of(*choices)
      choices = choices.flatten(1)
      raise ArgumentError, "one_of requires at least one generator" if choices.empty?
      return choices.first if choices.length == 1

      OneOfGenerator.new(choices)
    end

    # The parts `|` should flatten a generator into: its own alternatives if it
    # is already a one_of, otherwise just itself.
    def one_of_parts(generator)
      generator.is_a?(OneOfGenerator) ? generator.__send__(:choices) : [generator]
    end

    # Build an object out of drawn parts.
    #
    #   Generators.builds(Point, x: Generators.integers, y: Generators.integers)
    #   Generators.builds(->(a, b) { a..b }, Generators.integers, Generators.integers)
    #
    # The first argument is anything that responds to `call` or `new`.
    # Arguments that are not generators are passed through unchanged, so a
    # constant does not need wrapping in `just`.
    def builds(target, *parts, **keyword_parts)
      builder =
        if target.respond_to?(:call) then target
        elsif target.respond_to?(:new) then target.method(:new)
        else raise ArgumentError, "builds needs something callable or a class, got #{target.inspect}"
        end

      BuiltGenerator.new(
        builder,
        parts.map { |part| coerce(part) },
        keyword_parts.transform_values { |part| coerce(part) }
      )
    end

    # Accept a plain value anywhere a generator is expected.
    def coerce(value)
      value.respond_to?(:do_draw) ? value : just(value)
    end

    # Draw each generator in order and collect the values into an array.
    def tuples(*parts)
      TupleGenerator.new(parts)
    end

    # Build a generator from a block that draws as it goes.
    #
    # The block is handed the test case, so it can do anything a property can
    # — draw, assume, note:
    #
    #   ordered = Generators.composite do |t|
    #     low = t.draw(Generators.integers(max: 10))
    #     [low, t.draw(Generators.integers(min: low))]
    #   end
    def composite(&build)
      CompositeGenerator.new(build)
    end

    # Generate recursively-defined values such as trees or JSON documents.
    def recursive(leaf, &branch)
      raise ArgumentError, "recursive requires a branch block" unless branch

      RecursiveGenerator.new(coerce(leaf), branch)
    end

    private_class_method :coerce, :one_of_parts
    private_constant :MappedGenerator, :FlatMappedGenerator, :FilteredGenerator,
                     :JustGenerator, :BooleanGenerator, :WeightedBooleanGenerator,
                     :BytesGenerator, :SampledGenerator, :OneOfGenerator,
                     :TupleGenerator, :CompositeGenerator, :BuiltGenerator,
                     :IntegerGenerator, :TextGenerator, :FloatGenerator,
                     :ListGenerator, :UniqueListGenerator, :SetGenerator,
                     :PairGenerator, :HashGenerator, :RecursiveLeafBudget,
                     :RecursiveState, :RecursiveSubtreeGenerator, :RecursiveGenerator
  end
end
