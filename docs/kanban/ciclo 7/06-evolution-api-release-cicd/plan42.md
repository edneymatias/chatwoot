# Phase 42: Evolution API Release CI/CD Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish evolution-api's `<upstream-base>-ichatr.<N>` release tags (starting
`2.3.7-ichatr.1`) to the user's own Docker Hub namespace (`edneymatias/evolution-api`), triggered
by tag push, via a new dedicated GitHub Actions workflow and a `bin/ichatr-release` script that
mirrors the Chatwoot fork's own release script.

**Architecture:** A new tag-scoped workflow (`publish_docker_image_release.yml`) builds and pushes
the existing `Dockerfile` to `edneymatias/evolution-api` on any `*-ichatr.*` tag push, tagging the
image with both the exact tag and a floating `latest`. The existing `publish_docker_image.yml`'s
trigger is narrowed so it can never also fire on those tags. A new bash script computes, confirms,
and pushes the next release tag, leaving the workflow to take over from there.

**Tech Stack:** GitHub Actions (`docker/metadata-action@v5`, `docker/build-push-action@v6`,
existing QEMU/buildx/login actions already in the repo), bash.

## Global Constraints

- Tag format: `<upstream-base-version>-ichatr.<N>` (from `package.json`'s `version` field), no `v`
  prefix, hyphen-delimited — e.g. `2.3.7-ichatr.1`.
- `N` starts at 1 per base version, increments for same-base releases, implicitly resets when the
  base version itself changes (new prefix, no cross-base carry-over needed).
- Docker Hub target: `edneymatias/evolution-api`, using the already-configured
  `secrets.DOCKER_USERNAME` / `secrets.DOCKER_PASSWORD` in the `edneymatias/evolution-api` GitHub
  repo.
- No changelog generation, no GitHub Release creation, no CI test/lint gating before tag push — all
  explicitly out of scope per spec42.md.
- **Hard commit gate (this fork's standing constraint, `CLAUDE.md`):** no commits and no tag
  pushes until the user has validated locally and given explicit "ok." Every task below ends with
  changes staged/verified but uncommitted — do not run `git commit` or `git push` for any task
  without that explicit go-ahead.
- All work happens on the existing `feat/chatwoot-referral-attribution` branch in
  `/home/matias/dev/evolution-api` (same branch as Phase 40 — this phase adds CI/CD files, not
  application code, so no separate branch is required; confirm working tree state before starting,
  since Phase 40's uncommitted `chatwoot.service.ts` changes are expected to already be present and
  must not be touched or reverted by this plan's tasks).

---

### Task 1: New release-tag Docker publish workflow

**Files:**
- Create: `/home/matias/dev/evolution-api/.github/workflows/publish_docker_image_release.yml`

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces: a GitHub Actions workflow file, independently valid YAML, that later tasks don't
  depend on structurally (Task 2 touches a different file; Task 3's script only needs to know this
  workflow exists and reacts to tag pushes — no shared code).

- [ ] **Step 1: Write the new workflow file**

```yaml
name: Build Docker image (release)

on:
  push:
    tags:
      - "*-ichatr.*"

jobs:
  build_deploy:
    name: Build and Deploy
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    steps:
      - name: Checkout
        uses: actions/checkout@v5
        with:
          submodules: recursive

      - name: Docker meta
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: edneymatias/evolution-api
          tags: |
            type=raw,value={{tag}}
            type=raw,value=latest

      - name: Set up QEMU
        uses: docker/setup-qemu-action@v3

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Login to Docker Hub
        uses: docker/login-action@v3
        with:
          username: ${{ secrets.DOCKER_USERNAME }}
          password: ${{ secrets.DOCKER_PASSWORD }}

      - name: Build and push
        id: docker_build
        uses: docker/build-push-action@v6
        with:
          platforms: linux/amd64,linux/arm64
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}

      - name: Image digest
        run: echo ${{ steps.docker_build.outputs.digest }}
```

- [ ] **Step 2: Validate YAML syntax**

Run:
```bash
cd /home/matias/dev/evolution-api
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/publish_docker_image_release.yml'))" && echo "VALID YAML"
```
Expected: `VALID YAML` printed, no exception.

- [ ] **Step 3: Confirm the tag-pattern glob matches the target tag format**

Run (pure string-matching sanity check, no GitHub API needed — `fnmatch` implements the same glob
semantics GitHub Actions uses for tag filters):
```bash
python3 -c "
import fnmatch
assert fnmatch.fnmatch('2.3.7-ichatr.1', '*-ichatr.*')
assert fnmatch.fnmatch('2.3.7-ichatr.12', '*-ichatr.*')
assert not fnmatch.fnmatch('v2.3.7', '*-ichatr.*')
assert not fnmatch.fnmatch('2.3.7', '*-ichatr.*')
print('PATTERN OK')
"
```
Expected: `PATTERN OK` printed, no `AssertionError`.

- [ ] **Step 4: Leave uncommitted**

Do not run `git add` or `git commit` for this file — per the Global Constraints hard commit gate,
this waits for explicit user validation across all of this plan's tasks together (bundled at the
end, see Task 3's final step).

---

### Task 2: Narrow the existing tag-triggered workflow's pattern

**Files:**
- Modify: `/home/matias/dev/evolution-api/.github/workflows/publish_docker_image.yml` (the
  `on.push.tags` list, currently `- "*.*.*"`)

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces: nothing later tasks depend on — this is a standalone defensive fix (see spec42.md
  FR-002 for why: the current pattern already matches `-ichatr.*` tags too, which this narrows).

- [ ] **Step 1: Read the current trigger block to confirm the exact line to change**

Run:
```bash
grep -n -A3 '^on:' /home/matias/dev/evolution-api/.github/workflows/publish_docker_image.yml
```
Expected output includes:
```
on:
  push:
    tags:
      - "*.*.*"
```

- [ ] **Step 2: Change the tag pattern**

Edit `/home/matias/dev/evolution-api/.github/workflows/publish_docker_image.yml`, replacing:
```yaml
    tags:
      - "*.*.*"
```
with:
```yaml
    tags:
      - "v*.*.*"
```
No other line in this file changes — the `images: evoapicloud/evolution-api` and
`type=semver,pattern=v{{version}}` lines stay exactly as they are today.

- [ ] **Step 3: Validate YAML syntax**

Run:
```bash
cd /home/matias/dev/evolution-api
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/publish_docker_image.yml'))" && echo "VALID YAML"
```
Expected: `VALID YAML` printed.

- [ ] **Step 4: Confirm the narrowed pattern excludes ichatr tags but still matches upstream-style tags**

Run:
```bash
python3 -c "
import fnmatch
assert fnmatch.fnmatch('v2.3.7', 'v*.*.*')
assert not fnmatch.fnmatch('2.3.7-ichatr.1', 'v*.*.*')
assert not fnmatch.fnmatch('2.3.7', 'v*.*.*')
print('NARROWED PATTERN OK')
"
```
Expected: `NARROWED PATTERN OK` printed, no `AssertionError`.

- [ ] **Step 5: Leave uncommitted**

Same hard commit gate as Task 1 — no `git add`/`git commit` yet.

---

### Task 3: `bin/ichatr-release` script

**Files:**
- Create: `/home/matias/dev/evolution-api/bin/ichatr-release`

**Interfaces:**
- Consumes: `package.json`'s `version` field (already present, `"2.3.7"` today); local git tags
  matching `<version>-ichatr.*`; `git status --porcelain` for the dirty-tree check.
- Produces: on confirmed run, an annotated git tag pushed to `origin`, which Task 1's workflow
  reacts to. This task does not push anything during its own test steps — see Step 5 below, which
  tests the computation and prompt logic without actually confirming/pushing.

- [ ] **Step 1: Write the script**

```bash
#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

abort() {
  echo -e "\033[31mError: $1\033[0m" >&2
  exit 1
}

# Dirty tree check
if [[ -n "$(git -C "$repo_root" status --porcelain)" ]]; then
  abort "Working tree is dirty. Please commit or stash your changes before releasing."
fi

# Base version parsing
package_json="$repo_root/package.json"
[[ -f "$package_json" ]] || abort "package.json not found"

base_version="$(python3 -c "import json; print(json.load(open('$package_json'))['version'])")"
[[ -n "$base_version" ]] || abort "Could not determine base version from package.json"

# Fetch existing tags and compute the next tag
tag_prefix="${base_version}-ichatr."
mapfile -t existing_tags < <(git -C "$repo_root" tag -l "${tag_prefix}*")

next_tag_number=1
highest_tag=""

if [[ ${#existing_tags[@]} -gt 0 ]]; then
  max_number=0
  for tag in "${existing_tags[@]}"; do
    if [[ "$tag" =~ ^${tag_prefix//./\\.}([0-9]+)$ ]]; then
      n="${BASH_REMATCH[1]}"
      (( n > max_number )) && max_number=$n
    else
      abort "Malformed tag found: $tag. Please fix manually."
    fi
  done
  highest_tag="${tag_prefix}${max_number}"
  next_tag_number=$(( max_number + 1 ))
fi

next_tag="${tag_prefix}${next_tag_number}"

# Interactive confirmation prompt
echo "Current base version: $base_version"
echo "Highest existing tag: ${highest_tag:-None}"
echo
echo -e "Next tag: \033[32m$next_tag\033[0m"
echo
read -r -p "Are you sure you want to cut this release? This will push the tag to origin immediately. [y/N]: " confirm
confirm="$(echo "$confirm" | tr '[:upper:]' '[:lower:]')"

if [[ "$confirm" != "y" && "$confirm" != "yes" ]]; then
  abort "Release aborted by user."
fi

# Execute git tag and push
echo "Creating annotated tag $next_tag..."
git -C "$repo_root" tag -a "$next_tag" -m "Release $next_tag"

echo "Pushing tag to origin..."
git -C "$repo_root" push origin "$next_tag"

echo -e "\033[32mTag $next_tag created and pushed. CI pipeline will now build and publish the image.\033[0m"
```

- [ ] **Step 2: Make it executable**

Run:
```bash
chmod +x /home/matias/dev/evolution-api/bin/ichatr-release
```

- [ ] **Step 3: Verify bash syntax**

Run:
```bash
bash -n /home/matias/dev/evolution-api/bin/ichatr-release && echo "SYNTAX OK"
```
Expected: `SYNTAX OK` printed, no syntax error output.

- [ ] **Step 4: Verify the dirty-tree guard fires correctly**

The evolution-api working tree currently has an uncommitted change from Phase 40
(`src/api/integrations/chatbot/chatwoot/services/chatwoot.service.ts`), so this step doubles as a
real, non-mocked test of the guard:
```bash
cd /home/matias/dev/evolution-api
./bin/ichatr-release; echo "exit code: $?"
```
Expected: script prints `Error: Working tree is dirty. Please commit or stash your changes before releasing.` and exits non-zero (`exit code: 1`) — it must NOT reach the confirmation prompt, and must NOT create or push any tag.

- [ ] **Step 5: Verify the tag-computation logic in isolation (no push)**

The dirty-tree guard makes it impossible to reach the confirmation prompt in the current working
tree without violating the hard commit gate. Test the computation logic directly by extracting it
into a throwaway harness that stubs the dirty check, run against a disposable temp git repo (not
the real evolution-api repo) so no real tags or commits are touched:

```bash
tmp_repo="$(mktemp -d)"
cd "$tmp_repo"
git init -q
echo '{"version": "2.3.7"}' > package.json
git add package.json
git commit -q -m "init"

cp /home/matias/dev/evolution-api/bin/ichatr-release ./ichatr-release-test
chmod +x ./ichatr-release-test

# Case A: no existing tags -> expect next tag 2.3.7-ichatr.1
echo "n" | ./ichatr-release-test | grep -q "Next tag: " && echo "CASE A: prompt reached"
echo "n" | ./ichatr-release-test 2>&1 | grep -q "2.3.7-ichatr.1" && echo "CASE A: PASS (computed 2.3.7-ichatr.1)"

# Case B: existing 2.3.7-ichatr.1 and 2.3.7-ichatr.2 -> expect next tag 2.3.7-ichatr.3
git tag -a 2.3.7-ichatr.1 -m "r1"
git tag -a 2.3.7-ichatr.2 -m "r2"
echo "n" | ./ichatr-release-test 2>&1 | grep -q "Highest existing tag: 2.3.7-ichatr.2" && echo "CASE B: PASS (found highest)"
echo "n" | ./ichatr-release-test 2>&1 | grep -q "2.3.7-ichatr.3" && echo "CASE B: PASS (computed 2.3.7-ichatr.3)"

# Case C: declining the prompt must not create a tag
git tag -l | grep -c ichatr | grep -q "^2$" && echo "CASE C: PASS (no extra tag created after decline)"

cd - && rm -rf "$tmp_repo"
```
Expected: `CASE A: prompt reached`, `CASE A: PASS (computed 2.3.7-ichatr.1)`, `CASE B: PASS (found
highest)`, `CASE B: PASS (computed 2.3.7-ichatr.3)`, and `CASE C: PASS (no extra tag created after
decline)` all printed. This harness never touches the real `/home/matias/dev/evolution-api` repo
or pushes anything to `origin`.

- [ ] **Step 6: Leave uncommitted — report readiness for user validation**

Do not run `git add`/`git commit`/`git push` in the real `/home/matias/dev/evolution-api` repo for
any of this plan's three tasks. All three files (`publish_docker_image_release.yml`,
`publish_docker_image.yml`, `bin/ichatr-release`) are now written and individually verified
(YAML-valid, glob-pattern-correct, syntax-checked, and tag-computation-logic-verified via an
isolated harness), but nothing has been committed or pushed. Report to the user that all three are
ready for their own local review before requesting the explicit "ok" required to commit — and
separately, before they ever run `bin/ichatr-release` for real, that doing so will immediately tag
and push to `origin` once they answer `y` at its prompt, so the actual first release cut is a
distinct, deliberate action on their part, not an automatic consequence of this plan completing.

---

## Final note for the executing agent

Task 4 (running the real `bin/ichatr-release` against the live `edneymatias/evolution-api` repo,
watching the new workflow execute, and confirming the pushed image lands on Docker Hub) is
intentionally NOT a task in this plan — it is user-gated manual validation, identical in spirit to
Phase 40's Task 6, and must not be dispatched to a subagent or executed autonomously.
