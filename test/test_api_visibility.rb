# frozen_string_literal: true

require "minitest/autorun"
require "zizek"

class ApiVisibilityTest < Minitest::Test
  def test_entry_points
    assert_equal %i[
      alphabet alphabet_range check current_profile current_settings key_hash
      load_profile profile register_profile run with_profile
    ].sort, Zizek.singleton_class.public_instance_methods(false).sort
    refute_respond_to Zizek, :key_encode
    assert_raises(NoMethodError) { Zizek.key_encode(["name"]) }
  end

  def test_test_case_surface
    expected = %i[
      always assume boolean bytes clone_stream cost cover draw float integer
      next_key note sometimes start_span stop_span string target unreachable weighted
    ]
    assert_equal expected.sort, Zizek::TestCase.public_instance_methods(false).sort

    Zizek.check(examples: 1) do |test_case|
      refute_respond_to test_case, :draws
      refute_respond_to test_case, :record
      refute_respond_to test_case, :generation_us=
      assert_raises(NoMethodError) { test_case.draws }
      assert_raises(NoMethodError) { test_case.generation_us = 0 }
    end
  end

  def test_generator_factories_and_extension_protocol
    assert_equal %i[
      binary booleans builds composite floats hashes integers just lists none
      one_of recursive sampled_from sets text tuples weighted_booleans
    ].sort, Zizek::Generators.singleton_class.public_instance_methods(false).sort
    assert_equal [:Combinators], Zizek::Generators.constants(false)
    refute_respond_to Zizek::Generators.floats, :copy
    refute_respond_to Zizek::Generators.floats, :minimum
    union = Zizek::Generators.just(1) | Zizek::Generators.just(2)
    refute_respond_to union, :choices
    assert_raises(NoMethodError) { union.choices }

    generator_class = Class.new do
      include Zizek::Generators::Combinators

      def do_draw(test_case)
        test_case.start_span("custom")
        test_case.integer(1, 3)
      ensure
        test_case.stop_span
      end
    end
    generator = generator_class.new.map { |n| n * 2 }
    assert_respond_to generator, :do_draw
    Zizek.check(examples: 10, seed: 1) do |test_case|
      assert_includes [2, 4, 6], test_case.draw(generator)
    end
  end

  def test_internal_constants_are_private
    {
      Zizek => %i[Core Shell Profiles Draw ChoiceSpan UNICODE],
      Zizek::TestCase => %i[MAX_CLONE_DEPTH REJECT_RETRY REJECT_STOP REJECT_INVALID],
      Zizek::Stateful => %i[FeatureFlags ValuesReusable ValuesConsumed STOP_PROBABILITY],
      Zizek::Database => %i[ENTRY_PATTERN NAME_FILE]
    }.each do |namespace, names|
      names.each do |name|
        refute_includes namespace.constants(false), name
        assert_raises(NameError) { namespace.module_eval("#{namespace.name}::#{name}") }
      end
    end
  end

  def test_settings_and_database_helpers_are_private
    refute_respond_to Zizek::Settings.new, :effective_seed
    refute_respond_to Zizek::Settings, :property_identity
    %i[resolve digest shortlex atomic_write].each do |name|
      refute_respond_to Zizek::Database, name
    end
    directory = Zizek::Database::Directory.new
    %i[key_path value_path].each { |name| refute_respond_to directory, name }
    %i[fetch save delete].each { |name| assert_respond_to directory, name }
  end

  def test_stateful_dsl_and_protocol_remain_public
    assert_equal %i[pool run], Zizek::Stateful.singleton_class.public_instance_methods(false).sort
    assert_equal %i[invariant property rule],
                 Zizek::Stateful::Machine.singleton_class.public_instance_methods(false).sort
    machine = Zizek::Stateful::Machine.new
    assert_respond_to machine, :rules
    assert_respond_to machine, :invariants
  end
end
