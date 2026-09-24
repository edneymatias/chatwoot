# Quickstart: Scout Playbook Loader and Boot Validation

Validation guide for this feature once implemented. Assumes the container stack is already up
(`docker compose up -d`) per `AGENTS.md`. No production playbook files ship in this phase
(`custom/playbooks/` starts empty — authoring is brief 06); the scenarios below use throwaway
files to prove the mechanism end-to-end.

## Prerequisites

- `docker compose up -d` (services: `rails`, `postgres`, `redis` at minimum).
- No new env vars, no new gem install beyond the existing `bundle install` in the `rails`
  container's entrypoint.

## Scenario 1 — A valid playbook set loads into a queryable catalog (US1)

```sh
docker compose exec rails bundle exec rails runner '
  dir = Dir.mktmpdir
  File.write(File.join(dir, "pausa.md"), <<~MD)
    ---
    name: pausa
    title: Cliente pediu pausa
    priority: 10
    trigger: >
      O cliente pediu para pausar a conversa.
    ---

    ## Passos

    1. Confirme a pausa e encerre educadamente.
  MD

  catalog = Custom::ScoutV2::Playbook::Loader.load_all(dir)
  pb = catalog.find_by_name("pausa")
  raise "load failed" unless pb.title == "Cliente pediu pausa" && pb.requires == [] && pb.exits == {}
  puts "OK: loaded #{catalog.playbooks.size} playbook(s), ordered=#{catalog.ordered_by_priority.map(&:name)}"
'
```

**Expected outcome**: prints `OK: loaded 1 playbook(s), ordered=["pausa"]`; no exception.

## Scenario 2 — Boot fails loudly on a broken reference (US2)

```sh
docker compose exec rails bundle exec rails runner '
  dir = Dir.mktmpdir
  File.write(File.join(dir, "broken.md"), <<~MD)
    ---
    name: broken
    title: Quebrada de propósito
    priority: 10
    when_state:
      - nao_existe
    trigger: teste
    ---
    corpo
  MD

  catalog = Custom::ScoutV2::Playbook::Loader.load_all(dir)
  begin
    Custom::ScoutV2::Playbook::Validator.call!(catalog)
    raise "expected ValidationError, got none"
  rescue Custom::ScoutV2::Playbook::Validator::ValidationError => e
    puts "OK: #{e.message}"
  end
'
```

**Expected outcome**: prints a line naming `broken.md` and the unregistered predicate
`nao_existe`; the `raise "expected..."` line is never reached.

Repeat for the other violation kinds (duplicate `priority`, duplicate `name`, unknown `requires`
capability, undeclared `exit_<name>` token, unresolved `open_playbook(<name>)` token, missing/
non-integer `priority`) — each is a one-file-tweak variant of the same script, and is exactly what
`validator_spec.rb` automates permanently (see below).

## Scenario 3 — Boot validation actually blocks process readiness

```sh
docker compose exec rails sh -c '
  mkdir -p /tmp/broken_playbooks
  cat > /tmp/broken_playbooks/dup.md <<EOF
---
name: a
title: A
priority: 10
trigger: t
---
EOF
  cp /tmp/broken_playbooks/dup.md /tmp/broken_playbooks/dup2.md
  sed -i "s/name: a/name: b/" /tmp/broken_playbooks/dup2.md   # same priority 10, different name -> duplicate priority
  SCOUT_V2_PLAYBOOKS_DIR=/tmp/broken_playbooks bundle exec rails runner "puts :should_not_print"
'
```

**Expected outcome**: process exits non-zero before `:should_not_print` is printed, with the
`ValidationError` message naming both files and the duplicated `priority`. `Loader.load_all`
reads its directory from `ENV['SCOUT_V2_PLAYBOOKS_DIR']` when present, falling back to
`custom/playbooks`, so this scenario can point it at a scratch directory without touching the real
one. Pointing it at a directory that does not exist fails boot the same way, with `Errno::ENOENT`.

## Scenario 4 — A predicate is independently true/false without a model (US3)

```sh
docker compose exec rails bundle exec rails runner '
  ctx_with = Custom::ScoutV2::RoutingContext.new(opportunity: Opportunity.new(status: "open"), pending_fields: [])
  ctx_without = Custom::ScoutV2::RoutingContext.new(opportunity: Opportunity.new(status: "won"), pending_fields: [])
  predicate = Custom::ScoutV2::Predicates::OpportunityOpen.new
  raise "expected true" unless predicate.call(ctx_with) == true
  raise "expected false" unless predicate.call(ctx_without) == false
  puts "OK: opportunity_open true/false both correct"
'
```

**Expected outcome**: prints `OK: opportunity_open true/false both correct`.

## Running the permanent test suite (what actually gates merge)

```sh
docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec \
  custom/spec/services/custom/scout_v2/playbook/loader_spec.rb \
  custom/spec/services/custom/scout_v2/playbook/catalog_spec.rb \
  custom/spec/services/custom/scout_v2/playbook/validator_spec.rb \
  custom/spec/services/custom/scout_v2/predicates/evaluator_spec.rb \
  custom/spec/services/custom/scout_v2/predicates/opportunity_open_spec.rb \
  custom/spec/services/custom/scout_v2/predicates/pending_required_fields_spec.rb
```

**Expected outcome**: all examples green, covering — per brief §8 / spec.md's acceptance
scenarios — full and minimal frontmatter, verbatim body preservation, empty-vs-nil collection
defaults, catalog by-name/by-priority lookup, one example per FR-007–011/FR-017 violation kind, the
positive no-`exits` case, and true/false + AND-over-multiple-entries for both predicates.

Because the boot initializer runs on every Rails boot (research.md D9), this same suite also
proves FR-012/FR-013/SC-002: a healthy fixture set boots the specs with zero errors/warnings/LLM
calls, and a broken one fails the very first example that boots Rails.

## Cleanup

All scenarios above use `Dir.mktmpdir`/`/tmp` scratch directories — nothing touches the real
`custom/playbooks/` (which stays empty this phase) or requires manual cleanup.
