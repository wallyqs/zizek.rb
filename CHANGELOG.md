# Changelog

All notable changes to the Ruby package are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[semantic versioning](https://semver.org/spec/v2.0.0.html) — while the version
is `0.x`, the API may change in any release.

## [0.1.2] - 2026-10-28

### Fixed

- Shrinking a long byte-string or text draw no longer stalls. Converting a
  draw to and from its shortlex index took time roughly cubic in its length, so
  a draw of about 1 KB could keep a shrink running for minutes; byte indexes are
  now built and decoded in one linear pass, text indexes without full bigint
  products, and two text draws compare without building either index. Shrunk
  results and reproduce blobs are unchanged.

## [0.1.1] - 2026-10-27

First release of the Ruby package.

### Added

- `Zizek.check` — sequential property exploration with deterministic seeds,
  accepting either a lambda or a block.
- Recorded integer, boolean, byte-string, IEEE-754 float, and Unicode text
  draws, with boundary-biased integer generation.
- `Zizek::Generators` — composable, immutable generator builders with `map`
  and `filter`, plus `lists`, `sets`, `hashes`, and `lists(unique_by:)`.
- Per-choice shrinking with element-span and rule-span deletion, so a failure
  is reported at its minimal counterexample.
- Portable reproduce blobs: `Zizek.check(property, reproduce: blob)` replays
  the recorded example, including blobs emitted by the Go, Python, Rust, Zig,
  TypeScript, Java, C++, and Clojure packages.
- Choice punning and overrun detection on replay, with punned draws counted
  and reported on the failure.
- Coverage assertions (`test_case.cover`) that fail a completed run for an
  example it never produced.
- Stateful testing: rules, invariants, notes, and a default budget of 50
  successful steps, with reusable and consumed pools of arbitrary Ruby objects.
- `test_case.clone_stream` — a child test case drawing from a stream of its
  own, framed in the parent's blob and shrunk by the same schedule.
- Generation-phase span mutation, which duplicates same-label spans to
  discover repeated values and repeated state-machine operations.
- Assumption-based rejection with configurable limits.
- Runnable examples under `examples/`, including ports of Hypothesis's
  introductory property and all five top-level Hegel examples.
- Named draws: `test_case.draw(generator, name: :total)` reports the value in
  the failure's `Falsifying example:` line. A name is a label for the report
  only — it records no choice, so a named draw and an anonymous one shrink to
  the same blob.
- `Zizek::Failure` carries `values`, `seed`, and `costs`, and renders all
  three in its message alongside the cause and the reproduce blob.
- `Zizek.run` returns the outcome as a `Zizek::Result` instead of raising, for
  a harness that wants the verdict as a value. `Zizek.check` still raises.
- An example database: `database:` and `database_key:` on `Zizek.check` and
  `Zizek::Settings`, with `Zizek::Database::Directory` and
  `Zizek::Database::Memory`. A stored counterexample is replayed before
  anything is generated, and one that no longer reproduces is deleted. The
  layout — raw choice streams under a portable FNV-1a key — is shared with the
  Python and Go packages, so a failure found in one replays in the others. Off
  until asked for.
- `Zizek::Settings`, a frozen value object with `with`, rejecting unknown
  names at construction; named profiles via `register_profile`,
  `load_profile`, and `with_profile`; and `derandomize`, which derives the
  seed from where the property was written.
- Keyword generator factories — `integers(min:, max:, shrink_towards:)` and
  `floats(...)` — equivalent to the fluent builders, which remain. Bounded
  generators also accept a range: `integers(0..100)`, `integers(0...100)`,
  `integers(0..)`.
- `a | b` as `one_of`, flattening so a chain is one n-way choice;
  `generator.example` for a REPL; `Generators.builds` for assembling an object
  from drawn parts.
- `Zizek::Stateful::Machine` with `rule` and `invariant` class macros. Rule
  bodies run against the machine, subclasses inherit their parent's rules, and
  the DSL records the identical choice stream as a hand-built rule array.
- `zizek/minitest` and `zizek/rspec`: `property` defines a real test in each
  framework. A failed assertion is reported as a failure and a raised
  exception as an error, both carrying the falsifying example and the blob; a
  passing property registers an assertion.
- Four feature-walkthrough examples, each deterministic and gated by the
  package suite: `examples/coverage_assertions.rb` (the coverage assertion family),
  `examples/keyed_draws.rb` (keyed vs positional replay across a property
  edit), `examples/database_workflow.rb` (the example database's
  store/replay/self-clean cycle), and `examples/combinators.rb` (generator
  composition and shrinking through it).
- `GUIDE.md` sections for keyed draws, shrink costs, and cloned streams,
  which the feature guide previously omitted.

### Changed

Nothing here has shipped, so these are recorded for the reader of the diff
rather than as migrations.

- `Zizek.check`'s `require:` keyword is now `must_cover:`, and
  `Zizek::Coverage` takes `percent:` as a keyword.
- `Generators.composite` hands its block the test case rather than a bare
  draw lambda, so a composite can `assume` and `note` the way a property can.
- `Zizek::Failure.new` takes keyword arguments.
- `Zizek::Coverage` moved to `lib/zizek/settings.rb`; the constant path is
  unchanged.
- Enforce the Ruby public API boundary: engine namespaces and concrete
  generator classes are private constants; test-case bookkeeping, generator
  implementation readers, and configuration, database, and framework helpers
  are private or protected. Calls to these formerly public internals must
  migrate to the documented API. Generator `do_draw`, state-machine
  `rules`/`invariants`, and database `fetch`/`save`/`delete` remain public
  extension protocols.


### Fixed

- Documentation and comments referring to the old `require:` name for the
  `must_cover:` option.
- The `# frozen_string_literal: true` magic comment in
  `lib/zizek/generators.rb` sat mid-file, where it has no effect; it now
  covers the file.

### Notes

- Pure Ruby, no compiled extension, and no runtime dependencies.
- Exercised on Ruby 3.3. `required_ruby_version` is `>= 2.6` because the
  package uses nothing newer, but versions below 3.0 are not covered by CI.

[0.1.0]: https://github.com/wallyqs/zizek.rb/releases/tag/v0.1.0
