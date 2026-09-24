# Contract: Ruby Interfaces

Internal library surface this phase exposes. No HTTP/API contract — this is a purely internal Rails
module; the contract is the public method signatures later phases (brief 02 router, brief 03 turn
runner) build against without needing to know the loader/validator implementation.

## `Custom::ScoutV2::Playbook::Loader`

```ruby
Custom::ScoutV2::Playbook::Loader.load_all(dir = ENV['SCOUT_V2_PLAYBOOKS_DIR'].presence || Rails.root.join('custom/playbooks')) -> Playbook::Catalog
```

- Reads every `*.md` file directly under `dir` (non-recursive — one file per playbook, flat
  directory per design.md §4.3's tree).
- Never raises for anything inside a playbook file — a missing/invalid required field, an absent
  optional field, unparseable YAML, or a badly shaped `when_state`/`exits` — and always returns a
  `Catalog` for an existing directory, empty or not (research.md D2). Content it cannot use is
  recorded on `Playbook#load_errors` (unparseable YAML: frontmatter treated as `{}`; non-list
  `when_state`, a `when_state` entry that is neither a String nor a single-key mapping, non-mapping
  `exits`) instead of being silently dropped; `Validator` reports those entries.
- Raises `Errno::ENOENT` when `dir` does not exist: a missing or mistyped playbooks directory is a
  deployment bug and fails boot instead of loading zero playbooks. `custom/playbooks/.keep` keeps
  the default directory present in the repo and the image.
- Guarantees per `Playbook`: `when_state`/`requires`/`needs`/`tools`/`load_errors` are `Array`,
  never `nil`; `when_state` entries are `[String, String | nil]` pairs; `exits` is `Hash`, never
  `nil`; `body` is the exact substring after the closing frontmatter delimiter.

## `Custom::ScoutV2::Playbook::Catalog`

```ruby
catalog.playbooks           # -> Array<Playbook>
catalog.find_by_name(name)  # -> Playbook | nil
catalog.ordered_by_priority # -> Array<Playbook>, priority descending
catalog.each { |pb| ... }   # Enumerable
```

## `Custom::ScoutV2::Playbook::Validator`

```ruby
Custom::ScoutV2::Playbook::Validator.call!(catalog) -> catalog   # raises Validator::ValidationError, or returns catalog unchanged
```

- Raises `Custom::ScoutV2::Playbook::Validator::ValidationError` (a `StandardError`) exactly once
  per call, with every violation found across the whole catalog joined into `#message`
  (`\n`-separated, one line per violation, each line already naming the offending file(s) and the
  broken reference/value — see data-model.md).
- Returns the same `catalog` instance unchanged when there are zero violations (including the
  zero-playbooks case).
- Pure function of its `catalog` argument plus the two static collaborators below — no I/O, no
  network, no LLM call (FR-013).

## `Custom::ScoutV2::Predicates::Registry`

```ruby
Custom::ScoutV2::Predicates::Registry.registered?(name) -> true | false
Custom::ScoutV2::Predicates::Registry.resolve(name)      -> Class   # raises ArgumentError if unregistered
```

## `Custom::ScoutV2::Predicates::Base` (abstract)

```ruby
class Custom::ScoutV2::Predicates::SomePredicate < Custom::ScoutV2::Predicates::Base
  def call(ctx, arg = nil)
    # returns true | false
  end
end
```

## `Custom::ScoutV2::Predicates::Evaluator`

```ruby
Custom::ScoutV2::Predicates::Evaluator.call(when_state, ctx) -> true | false
```

- `when_state` is `Playbook#when_state` shape: `Array<[predicate_name, arg_or_nil]>`.
- Logical AND across all entries; vacuously `true` for `[]`.
- Never swallows an unregistered predicate name into `false` — `Registry.resolve` raising
  `ArgumentError` propagates (FR-016).

## `Custom::ScoutV2::Capabilities::Catalog`

```ruby
Custom::ScoutV2::Capabilities::Catalog.known?(name) -> true | false   # exact-string, case-sensitive
```

## Boot wiring (not a library call site — a process-boot side effect)

`config/initializers/scout_v2_playbooks.rb` calls
`Custom::ScoutV2::Playbook::Validator.call!(Custom::ScoutV2::Playbook::Loader.load_all)` inside
`Rails.application.config.after_initialize`; the directory (including the
`SCOUT_V2_PLAYBOOKS_DIR` override) is resolved only by `Loader.load_all`'s default argument. No
other code in the app is expected to call
`Loader.load_all` directly except this initializer and the RSpec fixtures that exercise it — later
phases consume the already-validated catalog through a to-be-defined accessor (out of scope here;
brief 02's concern).
