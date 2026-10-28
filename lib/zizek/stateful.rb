# frozen_string_literal: true

require_relative "generators"
require_relative "shell"

module Zizek
  module Stateful
    DEFAULT_STEP_COUNT = 50

    # Chance a free per-step "stop here?" boolean comes up true under the stop
    # protocols (1 and 2), which only a replay of an older blob still records,
    # and which a probe extends from the RNG once that blob runs out. New cases
    # record a "continue?" boolean instead, at
    # Core.stateful_continue_probability.
    STOP_PROBABILITY = 1.0 / 65536.0

    Rule = Struct.new(:name, :apply)

    # A state machine written as a class.
    #
    #   class QueueMachine < Zizek::Stateful::Machine
    #     def initialize
    #       @queue = RingQueue.new
    #       @model = []
    #     end
    #
    #     rule(:push) do |t|
    #       value = t.draw(Zizek::Generators.integers(min: 0, max: 99))
    #       @queue.push(value) && @model << value
    #     end
    #
    #     rule(:pop) do |t|
    #       t.assume(!@model.empty?)
    #       raise "wrong value" unless @queue.pop == @model.shift
    #     end
    #
    #     invariant(:sizes_agree) { @queue.size == @model.length or raise "drifted" }
    #   end
    #
    #   Zizek.check(QueueMachine.property, examples: 2_000)
    #
    # Rule bodies run with `self` bound to the machine, so they read and write
    # its state directly. `assume` inside a rule is a precondition: the step is
    # discarded and the run continues, rather than the whole example being
    # rejected.
    #
    # The array-returning `#rules` and `#invariants` protocol this is built on
    # is still supported; a machine that needs to compute its rules at runtime
    # can define those methods directly instead of subclassing.
    class Machine
      class << self
        def rule(name, &body)
          raise ArgumentError, "rule #{name.inspect} needs a block" if body.nil?

          declared_rules << Rule.new(name.to_s, ->(machine, test_case) { machine.instance_exec(test_case, &body) })
          name
        end

        def invariant(name, &body)
          raise ArgumentError, "invariant #{name.inspect} needs a block" if body.nil?

          declared_invariants << Rule.new(
            name.to_s, ->(machine, test_case) { machine.instance_exec(test_case, &body) }
          )
          name
        end

        def declared_rules
          @declared_rules ||= []
        end

        def declared_invariants
          @declared_invariants ||= []
        end

        # A property that runs one fresh machine per example.
        #
        # A machine holds mutable state, so the instance cannot be shared: each
        # example — and each shrink candidate — gets its own.
        def property(step_count: DEFAULT_STEP_COUNT, **new_args)
          machine_class = self
          lambda do |test_case|
            machine = new_args.empty? ? machine_class.new : machine_class.new(**new_args)
            Stateful.run(machine, test_case, step_count: step_count)
          end
        end

        # Subclasses start from their parent's rules rather than an empty list,
        # so a shared base machine can define the rules every variant has.
        def inherited(subclass)
          super
          subclass.instance_variable_set(:@declared_rules, declared_rules.dup)
          subclass.instance_variable_set(:@declared_invariants, declared_invariants.dup)
        end
      end

      private_class_method :declared_rules, :declared_invariants, :inherited

      def rules
        self.class.__send__(:declared_rules)
      end

      def invariants
        self.class.__send__(:declared_invariants)
      end
    end

    class FeatureFlags
      def initialize(test_case, rule_count)
        raw = test_case.__send__(:stateful_feature_probability_raw,
          Core.stateful_feature_generation_raw
        )
        @probability = Core.stateful_feature_probability(raw)
        @disabled = Array.new(rule_count)
        @candidates = (0...rule_count).to_a
      end

      def enabled?(test_case, index)
        test_case.start_span("stateful.feature_flag")
        decided = @disabled[index]
        forced = Core.stateful_feature_forced(
          @candidates.length,
          @candidates.include?(index),
          !decided.nil?,
          decided || false
        )
        begin
          disabled = forced.nil? ? test_case.weighted(@probability) : test_case.__send__(:forced_boolean, forced)
        rescue Exception # rubocop:disable Lint/RescueException
          test_case.stop_span
          raise
        end
        @disabled[index] = disabled
        @candidates.clear unless disabled
        @candidates.delete(index)
        test_case.stop_span
        !disabled
      end
    end

    # Execution-local pool of arbitrary host-language values.
    #
    # A variable's identity is a *recorded* choice rather than a host-side
    # counter, and a draw from the pool records the identifier it selected
    # rather than a position in the live list. That is what lets the shrinker
    # delete an earlier addition without changing what every later draw refers
    # to — see ir/stateful.zir's stable-identifier section. Before that,
    # deleting one addition renumbered every reference after it, so most
    # deletions produced a different rule sequence that no longer failed and
    # shrinking stalled far from minimal.
    class Pool
      def initialize
        @active = []
        @values = {}
      end

      def length
        @active.length
      end
      alias size length

      def empty?
        @active.empty?
      end

      # Add a value under a freshly drawn identifier.
      #
      # Takes the case because adding is now a *draw*: the identifier is
      # recorded in the choice stream rather than handed out by a host-side
      # counter, which is what lets a later reference to this variable keep
      # meaning this variable when an earlier addition is shrunk away.
      def add(test_case, value)
        variable_id = test_case.__send__(:fresh_id)
        @active << variable_id
        @values[variable_id] = value
        nil
      end

      def values_reusable
        ValuesReusable.new(self)
      end

      def values_consumed
        ValuesConsumed.new(self)
      end

      protected

      attr_reader :active, :values
    end

    class ValuesReusable
      def initialize(pool)
        @pool = pool
      end

      def do_draw(test_case)
        test_case.assume(!@pool.empty?)
        variable_id = test_case.__send__(:from_set, @pool.send(:active))
        @pool.send(:values).fetch(variable_id)
      end
    end

    class ValuesConsumed
      def initialize(pool)
        @pool = pool
      end

      def do_draw(test_case)
        test_case.assume(!@pool.empty?)
        variable_id = test_case.__send__(:from_set, @pool.send(:active))
        @pool.send(:active).delete(variable_id)
        @pool.send(:values).delete(variable_id)
      end
    end

    module_function

    def run(machine, test_case, step_count: DEFAULT_STEP_COUNT)
      rules = machine.rules.to_a
      test_case.assume(!rules.empty?)
      invariants = machine.invariants.to_a
      test_case.note("initial invariant check")
      check_invariants(machine, invariants, test_case)

      steps_drawn = 0
      steps_rejected = 0
      protocol = test_case.__send__(:stateful_protocol)

      # The first decision, which is forced, and the feature probability sit
      # before any step's span; each step's span then holds its rule probes,
      # the rule's own draws, and the decision that follows it. That makes
      # every step, the first included, one span the shrinker can delete
      # without misaligning the steps after it. Upstream's span starts at the
      # decision instead, which leaves the first step undeletable here:
      # deleting it takes the forced decision and the probability with it, and
      # a misread decision stops the run. The span tree is not part of the blob.
      return nil if stop_decision(test_case, protocol, steps_drawn, steps_rejected, step_count)

      feature_flags = protocol == 1 ? nil : FeatureFlags.new(test_case, rules.length)

      loop do
        test_case.start_span("stateful.rule")
        rejected = false
        begin
          if feature_flags.nil?
            index = draw_rule_index(test_case, rules.length)
          else
            index, feature_flags = select_rule(test_case, rules.length, feature_flags)
          end
          rule = rules[index]
          steps_drawn += 1
          test_case.note("step #{steps_drawn}: #{rule.name}")
          begin
            rule.apply.call(machine, test_case)
          rescue AssumptionRejected
            steps_rejected += 1
            rejected = true
            test_case.note("rule rejected by assumption")
          end
          check_invariants(machine, invariants, test_case) unless rejected
          stop = stop_decision(test_case, protocol, steps_drawn, steps_rejected, step_count)
        rescue Exception # rubocop:disable Lint/RescueException
          test_case.stop_span
          raise
        end
        test_case.stop_span(discarded: rejected)
        break if stop
      end
      nil
    end

    # Draw one round's decision and report whether the case stops. Protocol 3
    # records "continue?"; protocols 1 and 2 recorded "stop here?", and a
    # replay of one of their blobs keeps drawing that.
    def stop_decision(test_case, protocol, steps_drawn, steps_rejected, step_count)
      if protocol == 3
        forced = Core.stateful_continue_forced(steps_drawn, steps_rejected, step_count)
        proceed = if forced.nil?
                    test_case.weighted(Core.stateful_continue_probability)
                  else
                    test_case.__send__(:forced_boolean, forced)
                  end
        return !proceed
      end

      forced = Core.stateful_stop_forced(steps_drawn, steps_rejected, step_count)
      forced.nil? ? test_case.weighted(STOP_PROBABILITY) : test_case.__send__(:forced_boolean, forced)
    end
    private_class_method :stop_decision

    def draw_rule_index(test_case, rule_count)
      test_case.integer(0, rule_count - 1)
    end
    private_class_method :draw_rule_index

    def select_rule(test_case, rule_count, feature_flags)
      feature_flags ||= FeatureFlags.new(test_case, rule_count)
      known_bad = []
      Core.stateful_rule_probe_count.times do
        # A probe — the rule index and the flag it consults — is one span, so
        # the shrinker can delete a probe that landed on a disabled rule
        # without misaligning the draws after it. A misaligned continue
        # decision reads as a stop, so that deletion is the one that reaches
        # the minimal sequence; the span tree is not part of the blob.
        test_case.start_span("stateful.rule_probe")
        begin
          index = draw_rule_index(test_case, rule_count)
          enabled = !known_bad.include?(index) && feature_flags.enabled?(test_case, index)
        ensure
          test_case.stop_span
        end
        return [index, feature_flags] if enabled

        known_bad << index unless known_bad.include?(index)
      end

      max_good = Core.stateful_fallback_max_good(rule_count, known_bad.length)
      speculative = test_case.integer(0, max_good - 1)
      allowed = []
      rule_count.times do |index|
        next if known_bad.include?(index)
        next unless feature_flags.enabled?(test_case, index)

        allowed << index
        if Core.stateful_fallback_accept(allowed.length, speculative)
          return [test_case.__send__(:forced_integer, index), feature_flags]
        end
      end
      offset = test_case.integer(0, allowed.length - 1)
      [test_case.__send__(:forced_integer, allowed[offset]), feature_flags]
    end
    private_class_method :select_rule

    def check_invariants(machine, invariants, test_case)
      invariants.each do |invariant|
        test_case.note("invariant: #{invariant.name}")
        invariant.apply.call(machine, test_case)
      end
    end
    private_class_method :check_invariants

    def pool(_test_case)
      Pool.new
    end

    private_constant :FeatureFlags, :ValuesReusable, :ValuesConsumed, :STOP_PROBABILITY
  end
end
