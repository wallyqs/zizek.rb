<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/assets/zizek-rb-logo-dark.svg">
    <img src="docs/assets/zizek-rb-logo.svg" alt="Zizek.rb" width="320">
  </picture>
</p>

# Zizek for Ruby

This gem is the native Ruby runtime for Zizek property testing, based on
[Hegel](https://hegel.dev) and
[Hypothesis](https://hypothesis.readthedocs.io/en/latest/) and keeping them
as oracle implementations. It explores generated examples, records every
choice, shrinks the first failure, and raises a failure containing a portable
reproduce blob.

Roughly two thirds of the core behavior is compiled from the Hegel engine into
`lib/zizek/gen.rb`; the rest is a curated shell that aims to be idiomatic Ruby.
[dev.md](dev.md) describes the split.

> ⚠️ **Status: experimental.** Behavior and the public API can still change and
> be tweaked between releases.

## Install

```bash
gem install zizek
```

Or, in a `Gemfile`:

```ruby
gem "zizek", "~> 0.1"
```

## Quick start

```ruby
require "zizek"

property = lambda do |test_case|
  value = test_case.draw(Zizek::Generators.integers(-100..100), name: :value)
  raise "too large" unless value < 5
end

begin
  Zizek.check(property, examples: 200, seed: 1)
rescue Zizek::Failure => failure
  puts failure.message

  # Runs exactly the recorded, shrunk example and raises Failure again.
  begin
    Zizek.check(property, reproduce: failure.blob)
  rescue Zizek::Failure
  end
end
```

The failure says which values failed, not just that something did:

```
Falsifying example: (value=5)
RuntimeError: too large
reproduce with: Zizek.check(property, reproduce: "AAEAAAAACgEAAAAF")
seed: 1
```

`Zizek.check` also accepts a block, and `Zizek.run` returns the verdict as a
value instead of raising:

```ruby
Zizek.check(examples: 200) do |test_case|
  raise "too large" unless test_case.draw(Zizek::Generators.integers(-100..100)) < 5
end

Zizek.run(property, examples: 200, seed: 1).blob   # => "AAEAAAAACgEAAAAF"
```

## Generators

Generators compose with `map`, `filter`, `|`, and `tuples`, and add no hidden
choices, so a composed value shrinks and replays like a plain one:

```ruby
g = Zizek::Generators

request = g.tuples(
  g.sampled_from(%i[get post delete]),
  g.none | g.text(min: 1, max: 8),
  g.integers(0..10).filter(&:even?)
)

Zizek.check(examples: 200, seed: 7) do |test_case|
  method, resource, _retries = test_case.draw(request)
  raise "DELETE must name a resource" if method == :delete && resource.nil?
end
```

## Test frameworks

With Minitest, `property` defines a real test method:

```ruby
require "zizek/minitest"

class SplitBillTest < Minitest::Test
  include Zizek::Minitest

  property "the split is exact",
           total:  Zizek::Generators.integers(0..10_000),
           people: Zizek::Generators.integers(1..50) do |total, people|
    assert_equal total, Bill.split(total, people).sum
  end
end
```

With RSpec, it defines a real example:

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

## Stateful testing

Subclass `Zizek::Stateful::Machine` and declare rules and invariants; a
failure shrinks to the shortest sequence of steps that still fails:

```ruby
class Counter < Zizek::Stateful::Machine
  def initialize
    @value = 0
  end

  rule(:increment) do |test_case|
    @value += test_case.draw(Zizek::Generators.integers(0..10), name: :amount)
  end

  rule(:decrement) do |test_case|
    test_case.assume(@value.positive?)
    @value -= 1
  end

  invariant(:nonnegative) do
    raise "negative" if @value.negative?
  end
end

Zizek.check(Counter.property, examples: 500)
```

## Learn more

- [GUIDE.md](GUIDE.md) walks through every feature with runnable examples:
  settings and profiles, the example database, keyed draws, coverage
  assertions, pools, and more.
- [`examples/`](examples) holds runnable examples; each is listed in the
  guide.
- [dev.md](dev.md) covers the package layout, verification, and the upstream
  example ports.
- [CHANGELOG.md](CHANGELOG.md) records each release.

## Functionality available now

- Sequential property exploration with deterministic seeds.
- Generation-phase mutation that duplicates same-label spans to discover
  repeated values and repeated state-machine operations.
- Recorded integer, boolean, byte-string, IEEE-754 float, and Unicode text choices.
- Uniform narrow integer draws and swarm-biased wide ones.
- Composable generators accepted by `test_case.draw`.
- Assumption-based rejection with configurable limits.
- Exception and returned-`false` failure capture.
- Variable-length `Generators.lists` whose elements shrink by deletion, plus
  `Generators.sets`, `Generators.hashes`, and `lists(unique_by:)` for distinct
  elements.
- Per-choice shrinking plus element-span and rule-span deletion.
- Cloned streams: `test_case.clone_stream` returns a child test case drawing from
  a stream of its own, framed in the parent's blob and shrunk by the same
  schedule.
- Portable replay with choice punning and overrun detection, with punned
  draws counted and reported on the failure.
- An example database that stores counterexamples between runs and replays them
  before generating — in a layout the Python and Go packages share.
- State machines as classes (`Zizek::Stateful::Machine` with `rule` and
  `invariant`) or as hand-built rule arrays, with a default budget of 50
  successful steps (rejected rules spend an attempt, not a step).
- Reusable and consumed arbitrary Ruby-object pools.
- Named draws, reported as a falsifying example on the failure.
- Frozen `Settings` objects and named profiles, so a suite configures itself
  once instead of at every call site.
- `Zizek.run` for the verdict as a value, alongside `Zizek.check`.
- Minitest and RSpec integrations that define real tests in each framework.
- Runnable ports of Hypothesis's introductory example and all five top-level
  Hegel examples, including the ledger acceptance case.
