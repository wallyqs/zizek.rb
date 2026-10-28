# Zizek for Ruby: development notes

How the package is laid out and checked, for working on it rather than using
it. The [README](README.md) covers installation and the basics, and
[GUIDE.md](GUIDE.md) every feature.

## Core and shell

Everything on the load path lives under `lib/zizek/`, so installing the gem
adds exactly one name — `zizek` — to a user's `require` namespace.

- `lib/zizek.rb` is the entry point: `require "zizek"` loads the whole
  package.
- `lib/zizek/gen.rb` is generated from ZizekIR and owns deterministic choice
  indexing, boundary candidates, structural rewrites, stateful helpers,
  serialization, replay, and the shrink search's decisions: which request to
  make next, the candidate schedule, the cursor arithmetic, and the accept
  rule. It is pure — plain data in, plain data out, with no state, randomness,
  I/O, or exceptions. Do not edit it.
- `lib/zizek/shell.rb` owns every effect: random exploration, the clock,
  invoking Ruby code, notes, and exception mapping — including deriving the
  opaque bug-origin token (exception class + raise site over the cause chain)
  that the generated accept rule compares. It also drives the search and
  shrink loops, holding their cursors and schedules, and asks the core for
  each decision. That loop is written again in every language package; the
  shared conformance tables are what keep the packages in agreement.
- `lib/zizek/generators.rb` supplies immutable generator builders.
- `lib/zizek/stateful.rb` invokes rules and invariants, owns arbitrary Ruby
  values, and carries the `Machine` class macros.
- `lib/zizek/settings.rb` holds `Settings`, `Coverage`, and the profile
  registry. It has no dependency on the core, so configuration can be built
  and validated without loading it.
- `lib/zizek/version.rb` carries `Zizek::VERSION`, alone, so `zizek.gemspec`
  can read it without loading the core.
- `lib/zizek/minitest.rb` and `lib/zizek/rspec.rb` are the test-framework
  integrations. Neither is loaded by `require "zizek"`: a user requires the
  one their suite uses, so the gem depends on neither framework at runtime.
- `examples/` holds the runnable native and upstream-port examples;
  `examples/ledger.rb` is the end-to-end acceptance example and
  `examples/minitest_suite.rb` the framework one.
- `test/` is the package suite. It is not shipped in the gem: it reads shared
  conformance tables that live outside this package.

## Verify

The public API boundary is covered by `test/test_api_visibility.rb`, which
the main suite loads. Keep implementation helpers private and use protected
methods for access between test cases where needed. Internal modules and
concrete generator classes are private constants; their methods may remain
public for collaboration within the engine. The generated core is unchanged:
the handwritten shell marks its namespace private when loading it.

Cross-object calls to private methods within the engine explicitly use
`__send__`. White-box tests use `__send__` and `const_get` to inspect internals
without making them public again. The generated conformance tests follow the
same convention; change their templates in `emitter/` and regenerate them.

```bash
ruby -Ilib test/test_zizek.rb
ruby -Ilib test/test_minitest_integration.rb
ruby -Ilib test/test_rspec_integration.rb   # skips itself without rspec
ruby -Ilib examples/ledger.rb
ruby -Ilib examples/min_stack.rb
```

The emitted core is additionally compared with 103,171 Rust-reference vectors
across 180 kinds.

## Example database layout

What is stored is the **raw choice stream**, not the base64 blob, in
`<root>/<key digest>/<stream digest>` with both digests being the FNV-1a hash
`ir/keys.zir` already computes for keyed draws. That is what makes the
directory portable: the Python and Go packages write the same layout, so a
counterexample found by one replays in the others.

An entry that no longer parses is deleted along with ones that no longer
reproduce. Replays count as attempts but not toward `examples`, the coverage
verdict, or the health checks, all of which are statements about what the run
explored. An explicit `reproduce:` run touches the database not at all. Every
operation is best-effort: an unwritable directory never fails a test that
would otherwise pass.

## Upstream example ports

The package carries runnable ports of the examples used to compare Zizek with
Hypothesis and Hegel:

- [`examples/hypothesis_quickstart.rb`](examples/hypothesis_quickstart.rb)
  ports Hypothesis's introductory bounded-integer property. It discovers an
  arbitrary value at or above `50`, shrinks it to the exact boundary `50`, and
  replays the portable blob.
- [`examples/min_stack.rb`](examples/min_stack.rb) ports Hegel's deliberately
  broken minimum stack. The smallest failure is `push 0`, `push 0`, `pop`.
  Finding the two equal, unrestricted integers exercises generation-phase span
  mutation; structural shrinking then removes every unrelated operation.
- [`examples/stack.rb`](examples/stack.rb) ports Hegel's passing stack model,
  including a rule whose assumption may reject an operation without rejecting
  the whole generated example.
- [`examples/die_hard.rb`](examples/die_hard.rb) ports Hegel's water-jug state
  machine. It finds and shrinks the classic six-operation sequence leaving four
  litres in the five-litre jug.
- [`examples/multi.rb`](examples/multi.rb) ports Hegel's two-assertion example.
  It demonstrates that Zizek shrinks against the failure site it discovered
  instead of silently switching to the other assertion.
- [`examples/ledger.rb`](examples/ledger.rb) is the Hegel ledger port: two
  account creations followed by the buggy transfer of `1`.

Run them from the package root:

```bash
ruby -Ilib examples/hypothesis_quickstart.rb
ruby -Ilib examples/min_stack.rb
ruby -Ilib examples/stack.rb
ruby -Ilib examples/die_hard.rb
ruby -Ilib examples/multi.rb
ruby -Ilib examples/ledger.rb
```
