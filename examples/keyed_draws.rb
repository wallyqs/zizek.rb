# frozen_string_literal: true

# Keyed draws: a reproduce blob that survives editing the property.
#
# Demonstrates:
#   - naming a decision with `key: Zizek.key_hash(...)` so a replay finds it
#     by name instead of by position;
#   - a stored blob still reproducing its failure after a new draw is
#     inserted into the property, with the new draw's miss counted and
#     reported instead of raised; and
#   - the positional version of the same edit, where inserting a draw shifts
#     every choice after it and the old blob stops meaning what it recorded.
#
# The scenario is a client's retry policy. Version 1 draws a timeout and a
# retry count; the bug fires when the policy retries more than three times.
# Version 2 inserts a TLS flag between them — the kind of unrelated question
# a growing simulator adds every week.

require "zizek"

module KeyedDrawsExample
  module_function

  def check_policy(test_case, timeout, retries)
    test_case.note("timeout=#{timeout}s retries=#{retries}")
    raise "#{retries} retries would stampede the backend" if retries > 3
  end

  # Version 1: every decision is drawn under a stable name.
  def keyed_v1
    lambda do |test_case|
      timeout = test_case.integer(1, 30, key: Zizek.key_hash(:timeout))
      retries = test_case.integer(0, 9, key: Zizek.key_hash(:retries))
      check_policy(test_case, timeout, retries)
    end
  end

  # Version 2 inserts an unrelated keyed draw between the original two.
  def keyed_v2
    lambda do |test_case|
      timeout = test_case.integer(1, 30, key: Zizek.key_hash(:timeout))
      tls = test_case.boolean(key: Zizek.key_hash(:tls))
      retries = test_case.integer(0, 9, key: Zizek.key_hash(:retries))
      test_case.note("tls=#{tls}")
      check_policy(test_case, timeout, retries)
    end
  end

  # The same two versions, addressed positionally.
  def positional_v1
    lambda do |test_case|
      timeout = test_case.integer(1, 30)
      retries = test_case.integer(0, 9)
      check_policy(test_case, timeout, retries)
    end
  end

  def positional_v2
    lambda do |test_case|
      timeout = test_case.integer(1, 30)
      tls = test_case.boolean
      retries = test_case.integer(0, 9)
      test_case.note("tls=#{tls}")
      check_policy(test_case, timeout, retries)
    end
  end

  def find_failure(property)
    Zizek.check(property, examples: 300, seed: 5)
    raise "the retry stampede should be discovered"
  rescue Zizek::Failure => failure
    failure
  end

  def replay(property, blob)
    Zizek.check(property, reproduce: blob)
    raise "the recorded failure should still reproduce"
  rescue Zizek::Failure => failure
    failure
  end

  # Find the bug in version 1, then replay its blob against version 2.
  #
  # The keyed pair: `timeout` and `retries` resolve by name, so they read
  # exactly the values the blob recorded, wherever they now sit. The new
  # `tls` draw has no entry under its name — that is an edit to the property,
  # not a malformed blob — so it uses its simplest value and the failure
  # reports one key miss.
  def keyed_blob_survives_the_edit
    found = find_failure(keyed_v1)
    replayed = replay(keyed_v2, found.blob)
    raise "expected exactly one key miss" unless replayed.key_misses == 1
    raise "the recorded draws must be preserved" unless
      replayed.notes.include?(found.notes.first)

    [found, replayed]
  end

  # The same edit under positional addressing. The inserted boolean consumes
  # the entry recorded for `retries`, every draw after it is off by one, and
  # the stream ends before the property stops drawing: ReplayOverrun.
  def positional_blob_breaks_on_the_edit
    found = find_failure(positional_v1)
    begin
      Zizek.check(positional_v2, reproduce: found.blob)
      raise "the shifted replay should not run to completion"
    rescue Zizek::ReplayOverrun => overrun
      [found, overrun]
    end
  end
end

if $PROGRAM_NAME == __FILE__
  puts "== keyed: the blob outlives the edit =="
  found, replayed = KeyedDrawsExample.keyed_blob_survives_the_edit
  puts "version 1 failure:\n#{found.message}"
  puts "\nversion 2 replay of the same blob:\n#{replayed.message}"

  puts "\n== positional: the same edit shifts every later draw =="
  found, overrun = KeyedDrawsExample.positional_blob_breaks_on_the_edit
  puts "version 1 failure:\n#{found.message}"
  puts "\nversion 2 replay of the same blob: #{overrun.class}: #{overrun.message}"
end
