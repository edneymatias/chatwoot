# Feature Specification: Sync Script Audit Mode

**Feature Branch**: `008-sync-script-audit`

**Created**: 2026-08-03

**Status**: Draft

**Input**: User description: "Phase 10: Sync Script Update for Ciclo 2 Core-File Touches — extend `bin/sync-custom-module-hooks` with an `--audit` mode that detects core-file changes made during a development cycle that aren't yet reflected as `MANIFEST` entries, and close the gap found by the first audit run. Derived from `docs/kanban/ciclo 2/06-sync-script-update/spec10.md`."

## Clarifications

### Session 2026-08-03

- Q: When a modified model file has both annotate-gem schema-comment churn and a genuine,
  unrelated content change, should the exclusion rule still suppress it as a gap? → A: No —
  the annotate-gem exclusion applies only when a file's entire diff is annotate churn; any file
  with even one additional unrelated change must still surface as a gap.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Maintainer discovers untracked core-file touches before they're lost (Priority: P1)

A maintainer finishing a development cycle wants to know whether any core Chatwoot file was
changed to support the custom Kanban module without a corresponding entry being added to the sync
script's manifest. They run the script's audit mode against a base reference and get back a clear
list of which modified core files are already covered and which are gaps that still need a
manifest entry.

**Why this priority**: This is the entire point of the feature — without it, core-file touches
that accumulate during a cycle stay invisible until someone tries to apply the module to a fresh
checkout and it silently fails to wire in correctly.

**Independent Test**: Can be fully tested by running the audit mode against a known base
reference and confirming it correctly separates modified core files into "covered" (already has a
manifest entry) and "gap" (modified, no entry) buckets.

**Acceptance Scenarios**:

1. **Given** a core file was modified since the base reference and already has a `MANIFEST` entry,
   **When** the maintainer runs audit mode, **Then** that file is listed under "covered" with no
   action required.
2. **Given** a core file was modified since the base reference and has no `MANIFEST` entry,
   **When** the maintainer runs audit mode, **Then** that file is listed under "gap" as needing
   review.
3. **Given** a new (non-modified, newly added) file was introduced since the base reference,
   **When** the maintainer runs audit mode, **Then** that file is not flagged at all, since new
   files aren't core touches.
4. **Given** no `BASE_REF` is supplied, **When** the maintainer runs audit mode, **Then** it
   defaults to the merge-base of the current working branch and `develop`.

---

### User Story 2 - Maintainer excludes known noise from every future audit (Priority: P2)

A maintainer runs the audit and doesn't want to be told about files that are known,
expected churn unrelated to module wiring — regenerated schema files, tests, docs, non-English
locale files, and gem-generated annotation comments. These exclusions are declared once, as data,
so they apply automatically on every future cycle without being re-derived by hand each time.

**Why this priority**: Without this, every audit run would be swamped with false positives from
routine, expected file churn, making the real gaps hard to see and the audit tedious to use
repeatedly.

**Independent Test**: Can be fully tested by modifying a file matching one of the declared
exclusion patterns (e.g. a spec file, `db/schema.rb`, a non-English locale file, or a model with
only annotate-gem churn) and confirming the audit does not flag it as a gap even though it has no
manifest entry.

**Acceptance Scenarios**:

1. **Given** `db/schema.rb` was modified since the base reference, **When** the maintainer runs
   audit mode, **Then** it is never flagged as a gap.
2. **Given** a spec, doc, or non-English locale file was modified since the base reference,
   **When** the maintainer runs audit mode, **Then** it is never flagged as a gap.
3. **Given** a model file's only change since the base reference is annotate-gem schema-comment
   churn, **When** the maintainer runs audit mode, **Then** it is never flagged as a gap.
4. **Given** a maintainer wants to add a new exclusion pattern in a future cycle, **When** they
   update the exclusion data, **Then** no code branching logic needs to change to support it.

---

### User Story 3 - Maintainer closes the gaps found by the first real audit (Priority: P1)

Having run the audit for the first time against the actual history of ciclo 2, the maintainer adds
the missing `MANIFEST` entries for every genuine gap it found, then re-runs both the existing
`--check` mode and the new audit mode to confirm the module is fully wired and no gaps remain.

**Why this priority**: Running the audit without acting on its findings leaves the module
incompletely wired in any fresh checkout; closing the discovered gaps is what makes the custom
module actually work end-to-end, and it's the acceptance proof that the audit mechanism itself is
correct.

**Independent Test**: Can be fully tested by running `--check` after the manifest update and
confirming every entry (old and new) resolves against the current tree, then running `--audit`
against the same base/head pair used for the original findings and confirming it reports zero
gaps.

**Acceptance Scenarios**:

1. **Given** the manifest has been updated with entries for every file found as a gap in the
   initial audit, **When** the maintainer runs `--check`, **Then** every manifest entry (old and
   new) resolves successfully against the current tree.
2. **Given** the same manifest update, **When** the maintainer re-runs `--audit` against the
   original base/head range, **Then** it reports zero remaining gaps.

---

### Edge Cases

- What happens when a core file was modified and then reverted to match the base reference by the
  time the audit runs? It's not flagged, since there's no net diff for `git diff --name-status` to
  report.
- What happens when a file is renamed (not just modified) between the base reference and head? It
  is not treated as a modification gap, since the audit only inspects `M` (modified) status paths.
- What happens when a JSON insert point (e.g. `settings.json`, `automation.json`) needs a new key
  added into an existing object rather than a whole new file imported? The manifest entry for that
  file must express a comma-safe insert at an anchor, not a plain file-level replacement.
- What happens when the audit is run with a `BASE_REF` that has no merge-base with the current
  branch? This is an unsupported/misconfigured invocation and the script should fail loudly rather
  than silently produce a meaningless result.
- What happens when a model file's diff contains both annotate-gem schema-comment churn and an
  unrelated genuine change? The annotate-gem exclusion does not apply in this case; the file still
  surfaces as a gap needing review, since the exclusion only covers files whose entire diff is
  annotate churn.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The sync script MUST support an audit mode that accepts an optional base reference
  and defaults to the merge-base of the current working branch and `develop` when none is given.
- **FR-002**: The audit mode MUST compare the base reference against the current HEAD and working
  tree, and consider only modified (not newly added) core files as candidates for a gap.
- **FR-003**: The audit mode MUST exclude candidate files that match a declared set of permanent
  exclusion rules (regenerated schema files, spec/test/doc files, non-English locale files, and
  annotate-gem schema-comment churn) before evaluating them for coverage. For the annotate-gem
  rule specifically, the exclusion MUST apply only when a file's entire diff is annotate-gem
  churn; a file with any additional, non-annotate change MUST still surface as a gap.
- **FR-004**: The exclusion rules MUST be expressed as data (patterns), not hardcoded per-file
  branching logic, so future cycles can extend them without changing the audit's control flow.
- **FR-005**: For every remaining candidate file, the audit mode MUST report whether it is already
  covered by an existing manifest entry or represents a gap needing review, presented as two
  distinct buckets.
- **FR-006**: The manifest MUST gain an entry for each core file identified as a genuine gap by
  the first audit run, using the same anchor/insert mechanism as existing entries.
- **FR-007**: Manifest entries for files that require inserting into an existing JSON object (as
  opposed to importing a whole new file) MUST perform the insert in a comma-safe way that keeps
  the resulting JSON valid.
- **FR-008**: The existing check mode MUST continue to confirm that every manifest entry, old and
  newly added, resolves correctly against the current tree.
- **FR-009**: Re-running the audit mode against the same base/head range used to discover the
  original gaps MUST report zero remaining gaps once the manifest update has landed.

### Key Entities

- **MANIFEST**: The existing ordered list of anchor-based insert entries the sync script applies
  to a fresh checkout to wire in the custom Kanban module; each entry targets one core file.
- **Exclusion rule**: A declared pattern (path or content-based) identifying file changes that are
  never core-module wiring and should never be flagged as a gap, regardless of manifest coverage.
- **Audit finding**: The output of one audit run — a partition of modified core files into
  "covered" and "gap" buckets relative to a given base reference.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Running audit mode against the full history of a completed development cycle
  identifies 100% of core-file touches that lack a manifest entry, with zero false negatives among
  files not matching an exclusion rule.
- **SC-002**: Files matching a declared exclusion rule are never reported as gaps, across repeated
  audit runs, eliminating false-positive noise from routine expected churn.
- **SC-003**: After the manifest update lands, a fresh checkout of the repository can have the
  custom Kanban module fully wired in using only the sync script, with no manual core-file editing
  required.
- **SC-004**: Re-running the audit against the same range that originally found gaps reports zero
  gaps, confirming the mechanism and the manifest update are both correct.
- **SC-005**: The audit mechanism is reusable without modification at the start of every future
  development cycle, rather than requiring a one-off manual review each time.

## Assumptions

- The custom Kanban module's file layout (`custom/lib`, `custom/app/**`) and the existing
  `MANIFEST` anchor/insert mechanism from Phase 4 remain the wiring approach going forward; audit
  mode is additive tooling on top of that mechanism, not a replacement for it.
- `docker-compose.yaml`, `.gitignore`, and `AGENTS.md` are local/fork development-environment
  concerns, not module wiring, and are intentionally left out of the manifest and out of scope for
  gap-closing in this feature.
- The permanent exclusion patterns identified during this audit (schema regeneration, tests, docs,
  non-English locales, annotate-gem churn) are complete enough for the current codebase; new
  categories of expected noise can be added as data in future cycles without needing this feature
  to be revisited.
- The base reference `9d769dfcd` and head `7e666f57c` used for the first audit findings are a
  point-in-time snapshot for closing the currently known gap; the audit mechanism itself must work
  correctly for any future base/head pair, not just this one.
