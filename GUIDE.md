# Zizek for Ruby — feature guide

A walkthrough of every feature the Ruby runner currently supports, with
runnable examples for each. See [README.md](README.md) for installation and
[dev.md](dev.md) for the core/shell architecture; this guide is about *using*
the API.

## Public API

Use `require "zizek"` for the package, and `zizek/minitest` or `zizek/rspec`
for the optional framework integrations. The APIs described in this guide
are supported, including these extension protocols:

- Custom generators implement public `do_draw(test_case)`. Include
  `Zizek::Generators::Combinators` to add `map`, `filter`, `flat_map`, `|`,
  and `example` to your own generator.
- Custom state machines implement public `rules` and `invariants`, returning
  arrays of `Zizek::Stateful::Rule` objects.
- Custom example databases implement public `fetch`, `save`, and `delete`.

A property's test case exposes `draw`, `integer`, `float`, `boolean`,
`weighted`, `bytes`, `string`, `clone_stream`, `next_key`, `assume`, `note`,
`always`, `unreachable`, `sometimes`, `cover`, `cost`, `target`, `start_span`,
and `stop_span`. Use `Failure` or `Result` for reports and reproduce blobs.

Create generators through `Zizek::Generators` factories and configure them
with their fluent builders. Concrete generator classes, engine modules,
recorded draws, mutable bookkeeping, and helper methods are internal and
hidden with Ruby visibility rules. They are not supported extension points.

## Properties and `Zizek.check`

A property is a callable (or block) taking a test case. It fails by raising
any exception or by returning `false`.

```ruby
require "zizek"

property = lambda do |test_case|
  value = test_case.draw(
    Zizek::Generators.integers(-100..100)
  )
  raise "value must be less than five: #{value}" unless value < 5
end

Zizek.check(property, examples: 200, seed: 1)

# Or with a block:
Zizek.check(examples: 200, seed: 1) do |test_case|
  # ...
end
```

`Zizek.check` accepts keyword configuration:

| Keyword | Default | Meaning |
|---------|---------|---------|
| `examples:` | 100 | Valid (non-rejected) examples to run before declaring success. |
| `max_rejections:` | 458 | Initial rejection allowance; each valid example earns 100 more. |
| `max_shrinks:` | 500 | Accepted shrink candidates before the search stops. Zero disables the cap. |
| `max_stall:` | 200 | Consecutive rejected candidates before the search stops. Zero disables the cap. |
| `suppress_filter_too_much:` | `false` | Disable the early excessive-filtering health check. |
| `suppress_data_too_large:` | `false` | Disable the early choice-budget-overrun health check. |
| `suppress_large_base_example:` | `false` | Allow an all-simplest input that uses more than half the choice budget. |
| `suppress_too_slow:` | `false` | Disable the one-second cumulative generator-time health check. |
| `seed:` | random | Seed for random exploration. Reproduces a run on one machine; portable reproduction uses blobs instead. |
| `derandomize:` | `false` | Derive the seed from where the property was written, so a suite explores the same examples everywhere. |
| `must_cover:` | `[]` | Labels the completed run must have covered. See [Coverage assertions](#coverage-assertions). |
| `database:` | `nil` | Where counterexamples are stored between runs: a path, `":memory:"`, `true` for `.zizek/examples`, or a database object. See [The example database](#the-example-database). |
| `database_key:` | derived | The name a stored counterexample is filed under. Set it to share a directory with another language. |
| `reproduce:` | `nil` | A failure blob. When set, `check` replays exactly that example and runs nothing else. |
| `settings:` | active profile | A `Zizek::Settings` to start from; the keywords above override it. |

Every keyword except `reproduce:` and `settings:` is a field on
`Zizek::Settings`, and `check` takes its defaults from the active profile.
See [Settings and profiles](#settings-and-profiles).

On failure `check` raises:

- `Zizek::Failure` — a property failed; it is already shrunk and carries a
  reproduce blob;
- `Zizek::Flaky` — a property failed, then did not fail the same way when
  that example was replayed; it carries the original error and the unshrunk
  example's blob (`Zizek.run` reports it as outcome `:flaky`);
- `Zizek::TooManyRejections` — assumptions rejected too many examples;
- `Zizek::InvalidReplay` / `Zizek::ReplayOverrun` — a reproduce blob is
  malformed or does not match the property's draws.

```ruby
begin
  Zizek.check(property, examples: 200, seed: 1)
rescue Zizek::Failure => failure
  puts failure.blob
  puts failure.property_cause # the original exception; aliased as #cause
  puts failure.values         # the named draws: [[:value, 5]]
  puts failure.seed           # the seed this search ran under
  puts failure.notes
end
```

### `Zizek.run`, when the outcome is a value

`check` raises because a test that quietly ignored a counterexample would be
worse than no test. For code that wants the verdict instead — a harness
collecting blobs, a script comparing shrink quality, a property about a
property — `run` returns it:

```ruby
result = Zizek.run(property, examples: 200, seed: 1)

result.ok?           # => false
result.outcome       # => :failure
result.error         # => the Zizek::Failure
result.blob          # => "AAEAAAAACgEAAAAF"
result.values        # => [[:value, 5]]
result.notes         # => []
result.costs         # => {}
result.examples_run  # => 3
result.seed          # => 1
result.raise!        # raises what check would have raised
```

`outcome` is one of `:ok`, `:failure` (a counterexample), `:coverage` (a
`must_cover` label was missed), `:exhausted` (too many rejections), or
`:unhealthy` (a health check tripped). An invalid blob or a bad argument still
raises: those are mistakes in the call, not outcomes of the search.

## Settings and profiles

`Zizek::Settings` is a frozen value object. `with` returns a new one rather
than mutating, so a settings object can be shared without one caller
reconfiguring another:

```ruby
fast = Zizek::Settings.new(examples: 50)
thorough = fast.with(examples: 5_000, max_shrinks: 0)

Zizek.check(property, settings: thorough)
Zizek.check(property, settings: thorough, examples: 10)   # keywords still win
```

Unknown names raise at construction, so a misspelled option is a loud error
rather than one that silently did nothing:

```ruby
Zizek::Settings.new(exampels: 50)
# => ArgumentError: unknown setting: :exampels
```

A suite names the shapes it runs in once:

```ruby
# test_helper.rb
Zizek.register_profile(:dev, examples: 100)
Zizek.register_profile(:ci, examples: 5_000, derandomize: true)
Zizek.register_profile(:deep, base: Zizek.profile(:ci), examples: 50_000)
Zizek.load_profile(ENV["CI"] ? :ci : :dev)
```

`Zizek.check` then uses the active profile, and any keyword overrides it for
that call. Inside a suite prefer `with_profile`, which restores the previous
profile even if the block raises:

```ruby
Zizek.with_profile(:deep) { Zizek.check(property) }
```

`Zizek.current_settings` and `Zizek.current_profile` report what is active.
The registry is process-global, like Hypothesis's.

### Repeating a search versus replaying an example

Two different things, worth keeping apart:

- The **blob** replays one recorded example. It is portable: the same blob
  replays in the Go, Python, Rust, Zig, TypeScript, Java, C++, and Clojure
  packages. This is what a failure report is for.
- The **seed** repeats the whole search — the same examples in the same order
  — but only in this language and this version. Every failure now reports the
  seed it ran under.

`derandomize: true` derives the seed from the property's source location, so
a suite explores the same examples on every machine and in every CI run
instead of a fresh random set each time. An explicit `seed:` beats it.

## Low-level draws

`Zizek::TestCase` exposes the recorded primitive choices directly:

```ruby
value = test_case.integer(0, 100)                     # shrinks toward 0
value = test_case.integer(0, 100, shrink_towards: 10)
flag = test_case.boolean                              # shrinks toward false
payload = test_case.bytes(1, 4)                       # 1..4 bytes, shortlex
```

Every draw is recorded, which is what makes shrinking and blob replay work.
Narrow integer ranges (fewer than 256 values) are drawn uniformly, so a draw
that indexes a list picks every option equally often. Wide ranges use a
per-case swarm: the generated core supplies candidates such as the interval
endpoints and values near zero, so bugs at boundaries (like `1` in
`0..=1_000_000`) are found reliably.

## Generator objects

`test_case.draw(generator)` routes any object with a `do_draw(test_case)`
method through the test case:

```ruby
value = test_case.draw(Zizek::Generators.integers(-100..100), name: :value)
name = test_case.draw(Zizek::Generators.text(min: 1, max: 8), name: :name)
```

Passing `name:` puts the value in the failure's `Falsifying example:` line. It
is a label for the report only: it records no choice, so naming a draw cannot
change the blob or what any other language package replays.

- `Zizek::Generators.integers(min:, max:, shrink_towards:)` — full-range
  64-bit signed integers until bounded; `shrink_towards` moves the shrink
  destination. Also takes a range: `integers(-100..100)`.
- `Zizek::Generators.text(min:, max:, alphabet:)` — text over an alphabet, by
  default every Unicode scalar value. The bounds are lengths **in
  characters**, and `alphabet: "abc"` or
  `alphabet: Zizek.alphabet_range(0x20, 0x7E)` narrows the characters drawn.
  Values shrink towards `"0"`, then the digits and uppercase letters, so a
  minimal failing string is one you can retype.
- `Zizek::Generators.lists(element, min:, max:)` — a variable-length sequence.
  Each element is recorded as its own span, so the shrinker deletes whole
  elements — including ones in the middle — before it simplifies the values
  inside them.
- `Zizek::Generators.sets(element)`, `.hashes(keys, values)`, and
  `lists(element, unique_by: key)` — the same sequence with a distinctness
  constraint. A value that repeats one already drawn costs the *element*, not
  the example: its choices are discarded and another candidate is drawn. Asking
  for more distinct values than the element generator can produce rejects the
  example rather than looping, so
  `sets(integers(max: 1), min: 5)` reports "no valid examples"
  instead of hanging.
- `Zizek::Generators.floats(min:, max:, allow_nan:, allow_infinity:,
  smallest_nonzero_magnitude:)` — IEEE-754 doubles with portable shrinking.
  NaN and the infinities are off unless asked for: a property that has an
  opinion about them should say so.
- `Zizek::Generators.booleans`, `.weighted_booleans(probability)`, and
  `.binary(min:, max:)` — booleans shrinking towards `false` (the weight
  biases generation only, so a blob replays the same whatever probability
  produced it) and byte strings shrinking shortlex.
- `Zizek::Generators.builds(target, *parts, **keyword_parts)` — assemble an
  object out of drawn parts. The target is any class or callable, and an
  argument that is not a generator is passed through unchanged.
- `Zizek::Generators.recursive(leaf) { |subtrees| branch }` — bounded trees and
  other recursively-defined values; see [Recursive generators](#recursive-generators).

Every generator carries `map`, `filter`, `flat_map`, and `|` (which is
`one_of`, and flattens, so `a | b | c` is one three-way choice rather than
nested pairs). `flat_map` builds the *next generator* from each drawn value —
monadic bind:

```ruby
lists_sized_by_draw = Zizek::Generators.integers(0..5).flat_map do |length|
  Zizek::Generators.lists(Zizek::Generators.booleans, min: length, max: length)
end
```

Both draws share one `flat_map` span, so the shrinker can delete or simplify
the unit together, and the inner draws replay by the ordinary prefix rules.

The keyword form and the fluent builders are the same generator:

```ruby
Zizek::Generators.integers(min: 0, max: 100)
Zizek::Generators.integers.min_value(0).max_value(100)
```

Keywords are the preferred spelling at a creation site — the bounds are
self-documenting and there is no positional ambiguity between minimum,
maximum, and target. The builders remain for constructing a generator in
stages:

```ruby
generator = Zizek::Generators.integers
generator = generator.min_value(lower) if lower
generator = generator.max_value(upper) if upper
```

Builders are immutable: each configuration call returns a new generator, so
they can be shared and reused freely.

To see what a generator produces, without writing a test:

```ruby
Zizek::Generators.integers(0..100).example(seed: 3)   # => 24
```

`example` records nothing and cannot be replayed; it is for a REPL or a
docstring. A filter that rejects every attempt raises `Zizek::Unsatisfiable`
rather than looping.

If a property draws often enough that the `Zizek::Generators.` prefix is
noise, include the module:

```ruby
class SplitBillTest < Minitest::Test
  include Zizek::Generators   # integers, text, lists, ... without the prefix
end
```

### Recursive generators

`recursive` takes a generator for leaf values and a block that receives the
generator for child subtrees. The block returns a generator that combines one
or more children into the same result type:

```ruby
Tree = Struct.new(:value, :left, :right, keyword_init: true)

leaves = Zizek::Generators.integers(0..9).map do |value|
  Tree.new(value: value)
end

trees = Zizek::Generators.recursive(leaves) do |subtrees|
  Zizek::Generators.composite do |test_case|
    Tree.new(
      left: test_case.draw(subtrees),
      right: test_case.draw(subtrees)
    )
  end
end
trees = trees.max_depth(6).max_leaves(32)

tree = test_case.draw(trees)
```

The defaults are a maximum branch depth of 32 and at most 100 leaves.
`max_depth(0)` produces leaves only; `max_leaves` bounds the total base values,
not the number of branch nodes. An attempt that exceeds the leaf budget is
discarded and retried with a lower branching probability. If bounded retries
cannot construct a value, the example is rejected like a failed assumption.

Every subtree occupies a `recursive` span. The shrinker can therefore replace
an outer tree with one of its descendants, hoisting a deeply nested witness to
the root before simplifying its leaves. A leaf forced by `max_depth` is still a
recorded decision, so replay and the shrinker's choice positions stay aligned.

### Shrink targets

By default integers shrink toward 0 (clamped into the interval). With
`shrink_towards`, the reported counterexample is the failing value closest to
your target rather than the smallest one:

```ruby
value = test_case.draw(
  Zizek::Generators.integers(min: -1000, max: 1000, shrink_towards: 500)
)
# if the property fails for value > 700, the failure shrinks to exactly 701
```

Run [`examples/tour.rb`](examples/tour.rb) to watch this happen.

## Assumptions

`test_case.assume(condition)` rejects the current example when the condition
is falsy. Rejection is control flow, not failure: `check` keeps generating
until it has run `examples` valid examples or exceeds the adaptive rejection
budget `max_rejections + 100 * valid`, at which point it raises
`Zizek::TooManyRejections`.

```ruby
value = test_case.integer(0, 100)
test_case.assume(value.even?) # odd draws are discarded, not failed
```

Shrinking respects assumptions too: a shrink candidate that gets rejected is
skipped, so the shrunk counterexample always satisfies every assumption.

## Coverage assertions

A property can pass vacuously: the branch it exists to test never executes,
and the run goes green. `test_case.sometimes(label, condition)` turns that
silent gap into a failure — the condition must hold in at least one valid
example of the run — and `test_case.cover(label, condition, percent:)`
requires a rate. The verdict is per run, not per example; observations from
rejected or overrun examples are discarded with the rest of the example.
Labels whose call site may itself never execute are declared up front:

```ruby
Zizek.check(property, must_cover: [Zizek::Coverage.new("overflow path"),
                                Zizek::Coverage.new("cache hit", percent: 30)])
```

A missed requirement raises `Zizek::FailedCoverage` naming the label and
counters — no counterexample, so no blob or shrinking; the same seed
reproduces the same verdict. The per-example half is sugar over ordinary
failure: `test_case.always(label, condition)` fails the example the moment
its condition does not hold (and, holding, counts as covering its label, so
pairing it with `must_cover:` also demands the site be reached), while
`test_case.unreachable(label)` fails the example that reaches it, shrinking
to the simplest reaching input. The accept rule is compiled from
`ir/lifecycle.zir`, so every language agrees on it.

## Notes

`test_case.note(message)` attaches a diagnostic line to the current example.
Notes are collected per example and reported on the shrunk failure — both in
`failure.notes` and in the rendered `Trace:` section — so they describe the
*minimal* example, not the noisy first one.

```ruby
test_case.note("transfer #{amount} from #{source.inspect} to #{destination.inspect}")
```

## Failures, blobs, and replay

A shrunk failure carries a portable, base64 reproduce blob:

```ruby
begin
  Zizek.check(property, examples: 200, seed: 1)
rescue Zizek::Failure => failure
  # Replays exactly the recorded choices — nothing is random.
  Zizek.check(property, reproduce: failure.blob)
end
```

Blobs encode the recorded choice sequence, not the RNG seed, so they replay
bit-exactly across machines *and languages*: a blob printed by the Ruby runner
replays in the Go, Python, and Rust packages (the shared fixture
`AAEAAAAACgEAAAAF` replays the integer `5` in all four test suites, and the
ledger/queue examples pin cross-language blob fixtures of their own).

Replay is defensive:

- a structurally invalid blob raises `Zizek::InvalidReplay`;
- a blob that ends before the property stops drawing raises
  `Zizek::ReplayOverrun`;
- a choice of the wrong kind (or out of range) puns to the requested draw's
  unit value instead of failing, so replay stays deterministic while you edit
  the property.

A pun keeps the replay running, but it means the values you get back are not
the ones the blob recorded — and nothing in the values themselves says so. It
bites hardest when a draw's bounds depend on earlier draws, because then the
same blob can fit one run and pun on the next. Every replay therefore counts
its puns: `failure.puns` reports how many, and a non-zero count adds a warning line
to the rendered failure. Treat it as "this blob no longer reproduces what it
recorded", not as a hard error.

## Keyed draws

Positional replay gives a draw its meaning from how many draws came before
it, which is exactly right until the property changes shape: insert one new
draw and every recorded choice after it answers the wrong question. A keyed
draw is addressed by a *name* instead, so a blob keeps meaning what it
recorded while the property around it evolves:

```ruby
timeout = test_case.integer(1, 30, key: Zizek.key_hash(:timeout))
retries = test_case.integer(0, 9, key: Zizek.key_hash(:retries))
```

- `Zizek.key_hash(*components)` names a decision made at most once per
  example. Components are strings, symbols, or integers, hashed by the
  compiled encoding (`ir/keys.zir`), so the same name means the same entry
  in every language package.
- `test_case.next_key(*components)` appends an execution-local ordinal,
  counted *within that name*, for a decision made repeatedly —
  `next_key(:read, connection)` numbers that connection's reads
  independently of every other sequence.

On replay a keyed draw looks its name up wherever it sits in the stream, and
the positional cursor steps over keyed entries, so the two addressing modes
never shift each other. A name the blob does not carry means the property
changed, not that the blob is malformed: the draw uses its simplest value,
and the failure counts and reports the miss (`failure.key_misses`) instead
of raising.

[`examples/keyed_draws.rb`](examples/keyed_draws.rb) runs the whole
contrast: the same edit to a property breaks a positional blob with
`ReplayOverrun` while the keyed blob still reproduces its failure, one
counted miss and all.

## The example database

Set `database:` and a failure outlives the run that found it:

```ruby
Zizek.check(property, database: ".zizek/examples", database_key: "split_is_exact")
```

The next run replays every stored entry for that key *before* it generates
anything, so a bug found yesterday reproduces on the first example. An entry
that no longer reproduces — because the bug was fixed — is deleted on the
replay that failed to reproduce it, so the directory keeps itself current.

The database is off until asked for, and a profile turns it on for a whole
suite (`Zizek.register_profile(:local, database: ".zizek/examples")`).

What makes it more than a cache is the layout: raw choice streams, filed under
a hash the IR computes, which the Python and Go packages write identically. A
counterexample your Go service's suite found replays in your Ruby client's
suite out of one checked-in directory, provided both name the property the same
with `database_key:`. Left unset, the key is derived from where the property
was written — fine for one language, meaningless to another.

[`examples/database_workflow.rb`](examples/database_workflow.rb) runs the
whole cycle in a temporary directory: find and store, replay on the first
attempt of the next run, and watch the fixed bug's entry collect itself.

## Shrink costs

The shrinker's default order answers "what is the simplest *input* that
fails". A fault-injecting property usually wants a different question
answered first: "how few *faults* suffice?" Under the default order, turning
one injected fault off is worth exactly as much as making one integer a
little smaller, so the search may keep four faults because the stream around
them happens to be shorter.

`test_case.cost(label, amount = 1)` declares what an example spent:

```ruby
if test_case.boolean(key: test_case.next_key(:inject, site))
  test_case.cost(:reorder)   # this example spent one fault
  reorder(queue)
end
```

The shrinker then orders candidates by **total cost first** — a candidate
injecting one fewer fault wins even when its choice stream is longer — with
the ordinary stream order as the tiebreak, so a property that never calls
`cost` shrinks exactly as before. The failure reports the per-label
breakdown on `failure.costs` and in the rendered `cost:` line.

## Targeted generation

`cost` orders shrinking after a failure; `target` steers generation toward
one. A property records one finite score per label per example:

```ruby
value = test_case.integer(0, 100_000)
test_case.target(value)
raise "overflowed" if value >= 99_990
```

The run keeps the best-scoring valid example per label and, on a schedule,
hill-climbs its recorded choices — so a failing band at the far end of the
scored quantity is found in a fraction of the examples random search needs.
A failing climb trial shrinks and reports like any other counterexample, and
nothing new enters the blob. Target several quantities by naming them:
`test_case.target(depth, label: "depth")` — each label may be observed at
most once per example, and every score must be finite.

## Structural spans (advanced)

Framework-level code can group choices into labelled ranges so the shrinker
can delete whole semantic units at once:

```ruby
span_id = test_case.start_span("stateful.rule")
# ... draws ...
test_case.stop_span                  # or test_case.stop_span(discarded: true)
```

The state-machine runner uses spans for each rule, and
`Zizek::Generators.lists` uses one per element, which is why a 40-step failing
run shrinks to the three or six steps that matter and a 30-element list
shrinks to the one element that does. Most tests never call these directly.

## Cloned streams (advanced)

`test_case.clone_stream` returns a child test case that draws from a stream
of its own, occupying one choice position in the parent's. The child's draws
neither shift nor are shifted by the parent's, its stream is framed inside
the parent's blob with the engine's wire format, and the shrinker descends
into it with the same schedule — which is what makes it the seam a
concurrent runner would use, though today the child is drawn from
sequentially. Notes, costs, coverage, and the choice budget all belong to
the family rather than to one stream.

## Stateful testing

Subclass `Zizek::Stateful::Machine` and declare rules and invariants. A rule
body runs with `self` bound to the machine, so it reads and writes state
directly:

```ruby
class Counter < Zizek::Stateful::Machine
  def initialize(start: 0)
    @value = start
  end

  rule(:increment) do |test_case|
    @value += test_case.draw(Zizek::Generators.integers(0..10), name: :amount)
  end

  rule(:decrement) do |test_case|
    test_case.assume(@value.positive?)   # a precondition
    @value -= 1
  end

  invariant(:nonnegative) do
    raise "negative" if @value.negative?
  end
end

Zizek.check(Counter.property, examples: 500)
Zizek.check(Counter.property(start: 5), examples: 500)   # constructor arguments
```

`Machine.property` builds a fresh machine per example. A machine holds mutable
state, so the instance cannot be shared between examples — or between shrink
candidates, which is why `property` returns a lambda rather than taking an
instance.

A subclass inherits its parent's rules and invariants, so a shared base
machine can declare what every variant has:

```ruby
class LoggingCounter < Counter
  rule(:snapshot) { |_test_case| @log << @value }
end
```

`run` checks every invariant once before the first rule, then draws a capped
number of steps (at most 50, or `Counter.property(step_count: 200)`), picks a
rule per step, and re-checks every invariant after each successful rule. A
rule that calls `test_case.assume(false)` is recorded as rejected and skipped
without failing the run — that is what makes `assume` a precondition rather
than a rejection of the whole example.

Each rule invocation is its own structural span, so the shrinker deletes whole
commands and swaps adjacent ones before it simplifies the arguments inside
them. A six-step failure minimizes to the shortest sequence that still fails.

### The protocol underneath

`Stateful.run` asks a machine for `rules` and `invariants`, each an array of
`Zizek::Stateful::Rule` values whose lambdas receive the machine and the test
case. `Machine` builds those arrays from the class macros; a machine that
needs to compute its rules at runtime can define the two methods itself:

```ruby
class Counter
  def rules
    [Zizek::Stateful::Rule.new(
      "increment",
      ->(machine, test_case) { machine.increment(test_case) }
    )]
  end

  def invariants
    []
  end
end

Zizek.check { |test_case| Zizek::Stateful.run(Counter.new, test_case) }
```

Both forms record the identical choice stream, so a blob from one replays in
the other — and in every other language package.

### Pools

`Zizek::Stateful.pool(test_case)` holds values produced by earlier rules
behind portable choices, so shrinking and replay stay deterministic even
though the values are arbitrary Ruby objects:

```ruby
accounts = Zizek::Stateful.pool(test_case)
accounts.add(test_case, "a")

account = test_case.draw(accounts.values_reusable) # stays in the pool
ticket = test_case.draw(accounts.values_consumed)  # removed from the pool
```

Drawing from an empty pool rejects the current rule attempt (via `assume`), so
rules that need prerequisites simply retry on another step. Selection order is
generated-core semantics: selection by stable identifier.

## Using it from a test framework

### Minitest

```ruby
require "zizek/minitest"

class SplitBillTest < Minitest::Test
  include Zizek::Minitest

  property "the split is exact",
           total:  Zizek::Generators.integers(0..10_000),
           people: Zizek::Generators.integers(1..50) do |total, people|
    assert_equal total, Bill.split(total, people).sum
  end

  # No generators: the block is handed the test case.
  property "the queue stays consistent", settings: { examples: 2_000 } do |test_case|
    Zizek::Stateful.run(QueueMachine.new, test_case)
  end
end
```

`property` defines a real test method — `test_the_split_is_exact` — so `rake
test`, `-n`, seeds, reporters, and `setup`/`teardown` all work unchanged. The
block runs with `self` bound to the test instance, so ordinary assertions are
available, and a passing property registers one so it is not
indistinguishable from a test that forgot to assert.

Each generator keyword becomes a named draw, so the failure names the values:

```
  1) Failure:
SplitBillTest#test_the_split_is_exact:
Falsifying example: (total=1, people=2)
Minitest::Assertion: Expected: 1
  Actual: 0
reproduce with: Zizek.check(property, reproduce: "AAIAAAAACgEAAAABAAoBAAAAAg==")
```

A failed assertion is reported as a Minitest **failure**; a raised exception
stays an **error**, so a bug in the code under test is not relabelled as a
failed assertion. `settings:` is reserved and cannot be a generator name.

Two properties in one class cannot share a description: the second would
silently overwrite the first's method, so it raises instead.

### RSpec

```ruby
require "zizek/rspec"

RSpec.describe Bill do
  property "the split is exact",
           total:  Zizek::Generators.integers(0..10_000),
           people: Zizek::Generators.integers(1..50) do |total, people|
    expect(described_class.split(total, people).sum).to eq(total)
  end
end
```

`property` defines a real example, so filters, tags, formatters, `let`, and
`before` hooks work unchanged, and the block runs in the example's own context.
A failed expectation is re-raised as `ExpectationNotMetError` carrying the
falsifying example and the blob, so RSpec renders it as a failed expectation
rather than an unexpected exception.

Requiring the file registers the DSL on every example group. To scope it,
skip the require and add `config.extend Zizek::RSpec::DSL, type: :prop`.

RSpec is an optional development dependency: `lib/zizek/rspec.rb` is loaded
only if you require it, and the gem depends on neither framework at runtime.

## Runnable examples

Run from the package root:

| Example | Features | Run |
|---------|----------|-----|
| [`examples/roundtrip.rb`](examples/roundtrip.rb) | text generator, notes, minimal shrinking, blob replay | `ruby -Ilib examples/roundtrip.rb` |
| [`examples/tour.rb`](examples/tour.rb) | shrink targets, assumptions, boolean+bytes draws, rejection limits | `ruby -Ilib examples/tour.rb` |
| [`examples/queue.rb`](examples/queue.rb) | state machine, rule assumptions, invariants, failure capture, span shrinking | `ruby -Ilib examples/queue.rb` |
| [`examples/ledger.rb`](examples/ledger.rb) | full stateful slice: pools, text, cross-language blob fixture | `ruby -Ilib examples/ledger.rb` |
| [`examples/coverage_assertions.rb`](examples/coverage_assertions.rb) | `always`, `unreachable`, `sometimes`, `cover(percent:)`, `must_cover:` | `ruby -Ilib examples/coverage_assertions.rb` |
| [`examples/keyed_draws.rb`](examples/keyed_draws.rb) | keyed vs positional replay: the blob that survives editing the property | `ruby -Ilib examples/keyed_draws.rb` |
| [`examples/database_workflow.rb`](examples/database_workflow.rb) | the example database: store, replay-first, self-clean | `ruby -Ilib examples/database_workflow.rb` |
| [`examples/combinators.rb`](examples/combinators.rb) | `builds`, `sampled_from`, `map`, `filter`, `\|`, `composite`, shrinking through composition | `ruby -Ilib examples/combinators.rb` |
| [`examples/minitest_suite.rb`](examples/minitest_suite.rb) | the Minitest integration: named draws, per-property settings, the failure report | `ruby -Ilib examples/minitest_suite.rb` |

Each example is deterministic, asserts its own expected outcome in
`test/test_zizek.rb`, and prints the shrunk failure with its reproduce blob. The Go
and Python packages ship the same first four, shrinking to identical blobs.

`examples/minitest_suite.rb` is the exception: it is a Minitest suite, so it
exits non-zero, and one of its three properties fails on purpose. That failure
is the demonstration — the gate asserts the example still fails, because an
example that stopped failing would have stopped showing anything.
