# frozen_string_literal: true

# Composing generators: the blob stays portable, the shrinker stays sharp.
#
# Demonstrates:
#   - `builds` assembling a struct from drawn parts;
#   - `sampled_from`, `map`, `filter`, and `|` (one_of) layered on top;
#   - `composite` for a draw that depends on an earlier draw; and
#   - shrinking straight through the composition: combinators add no hidden
#     choices, so the minimal counterexample is minimal in every field at
#     once.
#
# Both scenarios are deterministic: fixed seeds, printed shrunk failures.

require "zizek"

module CombinatorsExample
  G = Zizek::Generators

  Request = Struct.new(:verb, :path, :body, :retries)

  module_function

  # A generator per field, assembled with `builds`:
  #   - `sampled_from` picks a verb, shrinking towards the first;
  #   - `map` turns drawn text into a path without recording extra choices;
  #   - `|` makes the body optional, shrinking towards the left (nil) side;
  #   - `filter` keeps only even retry counts, rejecting rather than failing.
  def requests
    G.builds(
      Request,
      verb: G.sampled_from(%i[get put delete]),
      path: G.text(min: 1, max: 8, alphabet: "abc").map { |name| "/#{name}" },
      body: G.none | G.text(min: 1, max: 6, alphabet: "xyz"),
      retries: G.integers(0..9).filter(&:even?)
    )
  end

  # The bug: the router forwards a DELETE body instead of rejecting it. The
  # shrunk request is minimal in every field the failure does not need —
  # shortest path, smallest retries — while `verb` stays `:delete` and `body`
  # stays present, because the failure needs them.
  def delete_with_a_body
    property = lambda do |test_case|
      request = test_case.draw(requests, name: :request)
      raise "refusing to forward a DELETE with a body" if
        request.verb == :delete && !request.body.nil?
    end

    begin
      Zizek.check(property, examples: 500, seed: 2)
      raise "the DELETE-with-body bug should be discovered"
    rescue Zizek::Failure => failure
      failure
    end
  end

  # `composite` is for a generator whose later draws depend on earlier ones:
  # here a meeting that must end no earlier than it starts. The block gets
  # the test case itself, so it can draw, assume, and note like a property.
  def meetings
    G.composite do |t|
      starts = t.draw(G.integers(0..23))
      ends = t.draw(G.integers(starts..23))
      [starts, ends]
    end
  end

  # The bug: the scheduler double-books the noon slot. The failure needs a
  # meeting spanning hour 12, so the shrunk example is the earliest start
  # with the earliest end that still covers it.
  def meeting_across_noon
    property = lambda do |test_case|
      starts, ends = test_case.draw(meetings, name: :meeting)
      test_case.note("meeting #{starts}:00-#{ends}:59")
      raise "the noon slot was double-booked" if starts <= 12 && ends >= 12
    end

    begin
      Zizek.check(property, examples: 300, seed: 1)
      raise "the noon double-booking should be discovered"
    rescue Zizek::Failure => failure
      failure
    end
  end
end

if $PROGRAM_NAME == __FILE__
  puts "== 1. builds + sampled_from + map + filter + | =="
  puts CombinatorsExample.delete_with_a_body.message
  puts "\n== 2. composite: dependent draws =="
  puts CombinatorsExample.meeting_across_noon.message
end
