---
name: "minimizing-test-reruns"
description: "Use when a task will run the same test suite multiple times during an edit cycle — before the first test run of a multi-file change, a TDD implementation task, or any convergence/fix-up task that touches several related files."
---

# Minimizing Test Reruns

## Overview

Running a test suite after every single edit burns tokens on redundant output (deprecation warnings, full suite boot, repeated failures) and encourages premature, uninformed edits. Batch changes, validate cheaply, test once per red/green transition.

## Core Pattern

1. **Plan**: Read every file you will touch, in full or by exact range, before editing. Write down what changes where and why.
2. **Batch edit**: Apply all planned edits — same file or across files — before any test run.
3. **Validate cheap**: Run a syntax-only check (`ruby -c file.rb`, a linter `--check`, `node --check`, etc.) instead of the test suite to catch typos and syntax errors.
4. **Test once**: Run the test suite a single time per red/green transition. Never re-run after each individual edit "to check progress."
5. **Summarize**: Report the result. Do not re-run "just to be sure" once green.

**Exception**: TDD's own red-phase run (confirm the test fails for the right reason) and green-phase run (confirm it now passes) are the two allowed runs — this is not a violation of "test once," it is the whole cycle.

## Quick Reference

| Situation | Do | Don't |
|---|---|---|
| About to touch 3 related files | Read all 3 fully, plan edits together | Edit file 1 → test → edit file 2 → test |
| Edit caused a NameError/syntax slip | `ruby -c` / linter first | Re-run full rspec to find a typo |
| Suite confirmed green | Move to the next task | Re-run "to be sure" |
| TDD red→green cycle | 2 runs total (red, green) | 3+ runs (edit-test loop) |
| Fixing several unrelated convergence tasks | Batch all edits per task, one test run per task | One test run per file touched |

## Common Mistakes

- **Testing after every edit** "just to check progress" — wastes tokens on repeated deprecation-warning noise and suite boot time; a syntax check catches most of what you were actually checking for.
- **Reading a file partially, editing, then re-reading it fully later** to understand context you skipped — read completely once, upfront, before editing.
- **Running the full suite when a syntax check would have caught the failure** — reserve full runs for behavior verification, not typo-hunting.
