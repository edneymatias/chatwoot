# Phase 0 Research: Sync Script Audit Mode

No open `NEEDS CLARIFICATION` markers remain in the Technical Context — the one substantive
ambiguity (annotate-gem exclusion granularity) was already resolved during `/speckit-clarify` and
is recorded in `spec.md`. This document captures the implementation-approach decisions needed to
move from spec to design.

## Decision: How `--audit` computes its diff

**Decision**: Run `git diff --name-status <BASE_REF>...HEAD` for the committed range, and
separately `git status --porcelain` (or `git diff --name-status HEAD`) to fold in working-tree
changes not yet committed, unioning the two file lists before filtering. Only entries with
status `M` are kept as candidates (per FR-002); `A` (added), `D` (deleted), and rename pairs are
dropped, matching the edge case in spec.md that renames are not treated as modification gaps.

**Rationale**: `git diff --name-status BASE_REF...HEAD` (triple-dot) compares against the
merge-base rather than HEAD directly, which is the correct semantics for "what changed on this
branch since it diverged from develop" — the same semantics the script already needs for the
default `BASE_REF`. Including the working tree matches spec10.md's original design note ("plus
working tree") and lets a maintainer audit before committing final changes.

**Alternatives considered**: Diffing only committed history (`BASE_REF..HEAD`, two-dot) — rejected
because it would miss the common case of running the audit mid-cycle with uncommitted changes
still in progress, which is exactly when the audit is most useful (before the "accumulate
untracked" problem starts).

## Decision: Default `BASE_REF` via merge-base

**Decision**: When no `BASE_REF` argument is given, shell out to
`git merge-base <current-branch> develop` and use its output as the base.

**Rationale**: This is what FR-001 specifies directly, and it's a single, well-understood git
primitive already implied by the source phase doc (`spec10.md` documents `9d769dfcd` as "today's"
merge-base). No alternative computation is simpler or more correct for "since this branch
diverged from develop."

**Alternatives considered**: Hardcoding a fixed historical ref — rejected, since the audit must
remain correct for any future cycle (per spec.md's Assumptions), not just the one that motivated
this feature.

## Decision: Exclusion rules as declarative data

**Decision**: Represent exclusion rules as an array of small data records — most as plain path
regexes/globs (schema.rb, `spec/**`, `*.md`, non-English locale directories), and the
annotate-gem rule as a distinct kind tagged to indicate it needs content inspection rather than a
path match alone. The audit's control flow iterates this array uniformly; only the
content-inspecting rule's evaluator differs, not the branching structure around it.

**Rationale**: FR-004 requires exclusions to be data, not hardcoded per-file branches, specifically
so a future cycle can add a new exclusion by appending to the array. Keeping one list (even though
one entry needs a different evaluator function) preserves a single iteration/exclusion pipeline
rather than two parallel mechanisms.

**Alternatives considered**: Two entirely separate mechanisms (a path-pattern list plus a
hardcoded `if file =~ /annotate/` special case) — rejected because it reintroduces exactly the
hardcoded-branching problem FR-004 exists to avoid, and would need its own explanation for why
one exclusion "cheats" the data-driven model.

## Decision: Detecting "entire diff is annotate-gem churn"

**Decision**: For files tagged as annotate-candidates (by path — the fixed list already named in
spec10.md, e.g. `app/models/category.rb`, `message.rb`, `platform_banner.rb`,
`channel/whatsapp.rb`, `enterprise/app/models/*`), fetch the actual patch content via
`git diff <BASE_REF>...HEAD -- <file>` (plus the working-tree equivalent when relevant) and check
that every added/removed line falls inside the annotate-gem schema-comment block (delimited by the
gem's standard `# == Schema Information` ... blank-line markers). If any changed line falls outside
that block, the file is treated as a gap per the clarification answer, not excluded.

**Rationale**: This is the only exclusion rule for which `git diff --name-status` alone (path +
status) is insufficient — annotate-gem regenerates a comment block inside otherwise
hand-maintained files, so path alone can't distinguish "only the annotate block changed" from "the
annotate block changed *and* someone edited the model." The clarification session settled that the
exclusion must be that precise, so the implementation must actually parse hunk boundaries against
the schema-comment block rather than assume any change to a listed file is safe to skip.

**Alternatives considered**: Excluding these files unconditionally by path (Option B from
clarification) — explicitly rejected by the user as the correct default, since it would silently
hide a real Kanban-related change riding along with routine annotate regeneration.

## Decision: Comma-safe JSON insert entries in `MANIFEST`

**Decision**: For the two JSON-file gaps (`settings.json`, `automation.json`), express the
manifest entry the same way as existing JS-object inserts already in `MANIFEST` (anchor a stable
existing line, insert new content immediately after it) but ensure the inserted text includes
its own leading/trailing comma placement so the result stays valid JSON — i.e., the anchor is the
line *before* the insertion point and the inserted text begins with a comma if it's not the last
key, mirroring how the script already inserts into JS object literals (e.g. the `featureFlags.js`
and `store/index.js` entries in the current `MANIFEST`).

**Rationale**: The existing anchor/insert mechanism is untyped text splicing (`content.sub(anchor,
"#{anchor}\n#{insert_text}")`) — it already works for JSON as long as the inserted fragment keeps
the surrounding structure valid, so no new mechanism is needed, only careful entry authoring.

**Alternatives considered**: A JSON-aware merge (parse, insert key, re-serialize) — rejected as
unnecessary complexity (Principle II) since the existing text-anchor mechanism already suffices
and this repo's manifest entries are hand-authored, reviewed text, not programmatically generated.
