# frozen_string_literal: true

# The example database: a counterexample that outlives the run that found it.
#
# Demonstrates:
#   - `database:` storing a shrunk failure's raw choice stream on disk;
#   - the next run replaying the stored entry before generating anything, so
#     yesterday's bug reproduces on the first attempt — no search, no seed;
#   - the fixed bug cleaning itself up: the entry that no longer reproduces
#     is deleted by the replay that failed to reproduce it; and
#   - the on-disk layout (`<key digest>/<stream digest>`), which the Python
#     and Go packages write identically, so a directory can be shared.
#
# The whole run works in a temporary directory and leaves nothing behind.

require "tmpdir"
require "zizek"

module DatabaseWorkflowExample
  # A name both sides of a shared directory agree on. Left unset, the key is
  # derived from where the property was written — stable across runs, but
  # meaningless to another language's suite.
  DATABASE_KEY = "sorted_merge_keeps_every_element"

  module_function

  # Merge two sorted arrays. Deliberate bug: the loop stops at the end of the
  # shorter input, dropping whatever the longer one still holds.
  def merge_buggy(left, right)
    merged = []
    a = 0
    b = 0
    while a < left.length && b < right.length
      if left[a] <= right[b]
        merged << left[a]
        a += 1
      else
        merged << right[b]
        b += 1
      end
    end
    merged # BUG: the unconsumed tail of the longer input is lost
  end

  # The property, parameterized on the merge under test so the same one can
  # first find the bug and then verify the fix.
  def property(merge)
    sorted = Zizek::Generators.lists(
      Zizek::Generators.integers(0..9), max: 4
    ).map(&:sort)

    lambda do |test_case|
      left = test_case.draw(sorted, name: :left)
      right = test_case.draw(sorted, name: :right)
      merged = merge.call(left, right)
      unless merged.length == left.length + right.length
        raise "merged #{left.inspect} and #{right.inspect} into #{merged.inspect}"
      end
    end
  end

  def stored_entries(root)
    Dir.glob(File.join(root, "*", "*")).reject { |path| File.basename(path).start_with?(".") }
  end

  def run_workflow
    Dir.mktmpdir("zizek-example-db") do |root|
      # Run 1: the search finds the bug, shrinks it, and stores the shrunk
      # choice stream under the database key.
      first =
        begin
          Zizek.check(property(method(:merge_buggy)),
                      examples: 300, seed: 1,
                      database: root, database_key: DATABASE_KEY)
          raise "the dropped-tail bug should be discovered"
        rescue Zizek::Failure => failure
          failure
        end
      entries = stored_entries(root)
      raise "one counterexample should be stored" unless entries.length == 1

      # Run 2: a different seed, but the stored entry is replayed before any
      # generation — the bug reproduces on the first attempt.
      second =
        begin
          Zizek.check(property(method(:merge_buggy)),
                      examples: 300, seed: 999,
                      database: root, database_key: DATABASE_KEY)
          raise "the stored counterexample should reproduce"
        rescue Zizek::Failure => failure
          failure
        end
      raise "the stored entry should be the first attempt" unless second.examples_run == 1
      raise "both runs should report the same blob" unless second.blob == first.blob

      # Run 3: the bug is fixed (a correct merge keeps every element, and for
      # this property concatenation is one). The stored entry no longer
      # reproduces, so the run deletes it and explores normally — the
      # directory keeps itself current.
      Zizek.check(property(->(left, right) { left + right }),
                  examples: 100, seed: 1,
                  database: root, database_key: DATABASE_KEY)
      unless stored_entries(root).empty?
        raise "the fixed bug's entry should have been collected"
      end

      [first, second]
    end
  end
end

if $PROGRAM_NAME == __FILE__
  first, second = DatabaseWorkflowExample.run_workflow
  puts "== run 1: found, shrunk, and stored =="
  puts first.message
  puts "\n== run 2 (different seed): replayed from the database on attempt " \
       "#{second.examples_run} =="
  puts second.message
  puts "\n== run 3 (bug fixed): the stale entry collected itself =="
end
