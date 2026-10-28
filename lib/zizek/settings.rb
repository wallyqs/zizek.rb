# frozen_string_literal: true

require "digest"

module Zizek
  # A label a completed run must have observed.
  #
  # A zero percent requires the label's condition to have held in at least one
  # valid example; a positive percent requires at least that share of them.
  class Coverage
    attr_reader :label, :percent

    def initialize(label, percent: 0)
      @label = label
      @percent = percent
      freeze
    end

    def ==(other)
      other.is_a?(Coverage) && other.label == label && other.percent == percent
    end
    alias eql? ==

    def hash
      [Coverage, label, percent].hash
    end

    def to_s
      percent.zero? ? "cover(#{label.inspect})" : "cover(#{label.inspect}, #{percent}%)"
    end
    alias inspect to_s
  end

  # How a property run explores, rejects, and shrinks.
  #
  # A settings object is a frozen value: `with` returns a new one rather than
  # mutating, so a profile can be shared between suites without one of them
  # reconfiguring the other. Unknown names raise, so a misspelled option is a
  # loud error at construction instead of an option that silently did nothing.
  class Settings
    # Every knob, with its default. The list is the schema: `Settings.new`
    # rejects anything not in it, and `to_h` round-trips through `new`.
    DEFAULTS = {
      examples: 100,
      # Initial rejection allowance; each valid example earns 100 more.
      max_rejections: 458,
      max_shrinks: 500,
      max_stall: 200,
      seed: nil,
      # Derive the seed from the property's identity instead of system
      # entropy, so a suite explores the same examples on every machine.
      derandomize: false,
      suppress_filter_too_much: false,
      suppress_data_too_large: false,
      suppress_large_base_example: false,
      suppress_too_slow: false,
      # Labels the completed run must have covered, whether or not any call
      # site for them ever executed.
      must_cover: [].freeze,
      # Where counterexamples are stored between runs. A path, ":memory:",
      # true for the default directory, nil to store nothing, or any object
      # responding to fetch/save/delete. Off by default: a library call that
      # wrote into the working directory unasked would be a surprise.
      database: nil,
      # The name a stored counterexample is filed under. A name chosen here is
      # portable, so another language's suite replays the same entry; left
      # unset, one is derived from where the property was written and stays
      # local to Ruby.
      database_key: nil
    }.freeze

    DEFAULTS.each_key { |name| attr_reader(name) }

    def initialize(**overrides)
      unknown = overrides.keys - DEFAULTS.keys
      unless unknown.empty?
        raise ArgumentError,
              "unknown setting#{"s" if unknown.length > 1}: #{unknown.map(&:inspect).join(", ")}"
      end

      DEFAULTS.each do |name, default|
        instance_variable_set(:"@#{name}", overrides.fetch(name, default))
      end
      @must_cover = normalize_coverage(@must_cover)
      validate!
      freeze
    end

    # A copy with some fields replaced. Returns self when nothing changes, so
    # the common "no overrides" path allocates nothing.
    def with(**overrides)
      return self if overrides.empty?

      Settings.new(**to_h, **overrides)
    end

    def to_h
      DEFAULTS.keys.each_with_object({}) { |name, out| out[name] = public_send(name) }
    end

    def ==(other)
      other.is_a?(Settings) && other.to_h == to_h
    end
    alias eql? ==

    def hash
      [Settings, to_h].hash
    end

    def inspect
      changed = to_h.reject { |name, value| DEFAULTS[name] == value }
      return "#<Zizek::Settings (defaults)>" if changed.empty?

      "#<Zizek::Settings #{changed.map { |name, value| "#{name}=#{value.inspect}" }.join(", ")}>"
    end

    # The seed a random run will use and report back.
    #
    # An explicit seed wins. A derandomized run derives one from the property's
    # identity, so the same test explores the same examples on every machine.
    # Otherwise one is drawn from system entropy — reported on the failure, so
    # a run that found something can at least be repeated.
    def effective_seed(property)
      return seed unless seed.nil?
      return Random.new_seed & MASK64 unless derandomize

      Digest::SHA256.digest(Settings.__send__(:property_identity, property))
                    .unpack1("Q<")
    end

    # What a derandomized seed is derived from: where the property was written,
    # so moving a test to another machine keeps its examples and writing a
    # second test in the same file gets its own.
    def self.property_identity(property)
      location = property.source_location if property.respond_to?(:source_location)
      return "#{location[0]}:#{location[1]}" if location

      property.inspect
    end

    MASK64 = (1 << 64) - 1
    private_constant :MASK64
    private :effective_seed
    private_class_method :property_identity

    private

    def normalize_coverage(entries)
      entries.map do |entry|
        next entry if entry.is_a?(Coverage)
        next Coverage.new(entry) if entry.is_a?(String) || entry.is_a?(Symbol)

        raise ArgumentError,
              "must_cover takes Zizek::Coverage entries or label strings, got #{entry.inspect}"
      end.freeze
    end

    def validate!
      raise ArgumentError, "examples must be positive" unless examples.is_a?(Integer) && examples.positive?
      raise ArgumentError, "max_rejections must be non-negative" if max_rejections.negative?
      raise ArgumentError, "max_shrinks must be non-negative" if max_shrinks.negative?
      raise ArgumentError, "max_stall must be non-negative" if max_stall.negative?
      raise ArgumentError, "seed must be an Integer or nil" unless seed.nil? || seed.is_a?(Integer)

      # Resolving here rather than at run time makes a bad database a loud
      # error where it was configured, like every other option.
      Database.__send__(:resolve, database)

      must_cover.each do |required|
        next if required.percent >= 0 && required.percent <= 100

        raise ArgumentError, "required coverage percent must be between 0 and 100"
      end
    end
  end

  # Named settings profiles.
  #
  # A suite registers the shapes it runs in once, then selects one — from a
  # spec_helper, an environment variable, or a block — instead of repeating
  # the same six keywords at every call site.
  #
  #   Zizek.register_profile(:ci, examples: 1_000, derandomize: true)
  #   Zizek.load_profile(:ci) if ENV["CI"]
  #
  # The active profile is process-global, like Hypothesis's. Prefer
  # `Zizek.with_profile` over `load_profile` inside a suite: it restores the
  # previous profile even if the block raises.
  module Profiles
    DEFAULT = :default

    class << self
      def registry
        @registry ||= { DEFAULT => Settings.new }
      end

      def active
        @active ||= DEFAULT
      end

      attr_writer :active
    end
  end

  module_function

  # Register a profile and return it. Overwriting an existing name is allowed:
  # a spec_helper reloaded in the same process should not raise.
  def register_profile(name, base: nil, **overrides)
    base ||= Settings.new
    settings = base.with(**overrides)
    Profiles.registry[name.to_sym] = settings
    settings
  end

  def profile(name)
    Profiles.registry.fetch(name.to_sym) do
      known = Profiles.registry.keys.map(&:inspect).join(", ")
      raise KeyError, "unknown profile #{name.inspect}; registered: #{known}"
    end
  end

  # Make a profile the default for subsequent `check` calls, and return it.
  def load_profile(name)
    settings = profile(name)
    Profiles.active = name.to_sym
    settings
  end

  # The settings `check` uses when a call passes no overrides.
  def current_settings
    profile(Profiles.active)
  end

  def current_profile
    Profiles.active
  end

  # Run a block under a profile, restoring the previous one afterwards.
  def with_profile(name)
    previous = Profiles.active
    load_profile(name)
    yield
  ensure
    Profiles.active = previous
  end

  private_constant :Profiles
end
