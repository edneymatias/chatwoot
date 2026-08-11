# Evolution API Referral Patch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Patch Evolution API's Chatwoot connector to capture `sourceId`/`sourceType`/`mediaType`/`mediaUrl` from WhatsApp ad-reply metadata and forward them to Chatwoot as a normalized `referral` object in `content_attributes`, matching the WhatsApp Cloud API's field shape exactly.

**Architecture:** Single-file patch to `src/api/integrations/chatbot/chatwoot/services/chatwoot.service.ts` in the external fork `/home/matias/dev/evolution-api` (branch: new feature branch off `main`@`fa09d378`). Four sequential, additive changes to that file: (1) widen the raw field extraction in `getAdsMessage`, (2) add a small pure function that normalizes those raw fields into Cloud-API-shaped keys, (3) extend `sendData`'s signature with a trailing optional `referral` param and merge it with existing `content_attributes` before one single `FormData` append, (4) wire the ads-message call site to pass the normalized object through. No Chatwoot-side (this repo) changes — already confirmed unnecessary in spec40.

**Tech Stack:** TypeScript (Evolution API fork), `tsc --noEmit` + `eslint` as the verification gates (this fork has no test framework — confirmed in spec40's Validation section; `npm test` points at a nonexistent file).

## Global Constraints

- Branch from fork `main` at current tip (`fa09d378`, `package.json` version `2.3.7`) — NOT from any upstream `dev` tree. (spec40 header)
- Every new field on `AdsMessage`/`referral` is optional and populated only when Meta/Baileys actually sent it — no fabricated defaults. (spec40 FR-001, FR-002)
- `referral` object field names must be exactly: `source_id`, `source_type`, `source_url`, `headline`, `body`, `media_type`, `image_url` — matching Chatwoot's own (unmodified) Cloud API `referral` shape. (spec40 FR-002)
- `image_url` is sourced from `thumbnailUrl`, not `mediaUrl`. (spec40 FR-002)
- `referral` is omitted entirely from the payload when no field is present (mirrors Chatwoot's own `.present?` guard). (spec40 FR-002)
- New `sendData` parameter must be appended LAST (after existing `quotedMsg`) to avoid breaking the two call sites that already pass all 9 existing positional args. (spec40 FR-003, Impact analysis)
- `referral` and any existing `replyToIds` must be merged into a single object before a single `data.append('content_attributes', ...)` call — never two separate `append` calls for the same field name. (spec40 FR-003, Impact analysis)
- The existing image+caption ads-message UX is unchanged — `referral` is purely additive to `content_attributes`. (spec40 FR-004)
- Do NOT fix the pre-existing `isAdsMessage`/unconditional `thumbnailUrl` fetch bug (chatwoot.service.ts:2213-2215) — flagged, out of scope. (spec40 Out of scope)
- Do NOT commit or push in the Evolution API fork until the user has explicitly tested locally and given an explicit "ok" (project-wide CLAUDE.md workflow constraint, applies here too).

---

## File Map

- **Modify:** `/home/matias/dev/evolution-api/src/api/integrations/chatbot/chatwoot/services/chatwoot.service.ts`
  - `getAdsMessage` (currently lines 1724-1743) — widen raw extraction.
  - New private method `buildReferralAttributes` (placed directly after `getAdsMessage`) — normalize to Cloud API shape.
  - `sendData` (currently lines 1050-1119) — new trailing param + merge logic.
  - Ads-message call site (currently lines 2250-2259) — pass `quotedMsg` + new `referral` object.

No other files are touched. No new files are created (the normalization logic is a private method on the existing `ChatwootService` class, not a standalone module — it's a ~10-line pure mapping with a single call site, not worth splitting out per the project's "avoid one-use private helpers unless they hide real complexity" guidance... but here it DOES hide real complexity worth isolating: it's the one piece of business logic (the Cloud-API field-name contract) that Phase 41 will need to know matches exactly, so keeping it as its own named method — rather than inlining into the call site — makes that contract easy to find and reason about on its own).

---

### Task 1: Create the feature branch

**Files:** none (git operation only)

- [ ] **Step 1: Verify the fork is clean and at the expected tip**

```bash
cd /home/matias/dev/evolution-api
git status
git log -1 --oneline
```

Expected: clean working tree, HEAD at `fa09d378 docs(org): update nested submodule URLs from EvolutionAPI to evolution-foundation`. If HEAD differs, STOP and check with the user before proceeding (per spec40: must branch from this exact tip, not upstream dev).

- [ ] **Step 2: Create and switch to the feature branch**

```bash
git checkout -b feat/chatwoot-referral-attribution
```

- [ ] **Step 3: Confirm branch and clean tree**

```bash
git status
```

Expected: `On branch feat/chatwoot-referral-attribution`, nothing to commit.

---

### Task 2: Widen `getAdsMessage` to capture `sourceId`/`sourceType`/`mediaType`/`mediaUrl`

**Files:**
- Modify: `src/api/integrations/chatbot/chatwoot/services/chatwoot.service.ts:1724-1743`

**Interfaces:**
- Produces: `AdsMessage` interface gains 4 new optional fields (`sourceId?: string`, `sourceType?: string`, `mediaType?: string`, `mediaUrl?: string`) alongside the existing required `title`, `body`, `thumbnailUrl`, `sourceUrl`. `getAdsMessage(msg: any): AdsMessage` return shape is consumed by Task 3's `buildReferralAttributes`.

- [ ] **Step 1: Read the current method to confirm line numbers haven't drifted**

```bash
sed -n '1720,1745p' src/api/integrations/chatbot/chatwoot/services/chatwoot.service.ts
```

Expected output matches:
```ts
  private isInteractiveButtonMessage(messageType: string, message: any) {
    return messageType === 'interactiveMessage' && message.interactiveMessage?.nativeFlowMessage?.buttons?.length > 0;
  }

  private getAdsMessage(msg: any) {
    interface AdsMessage {
      title: string;
      body: string;
      thumbnailUrl: string;
      sourceUrl: string;
    }

    const adsMessage: AdsMessage | undefined = {
      title: msg.extendedTextMessage?.contextInfo?.externalAdReply?.title || msg.contextInfo?.externalAdReply?.title,
      body: msg.extendedTextMessage?.contextInfo?.externalAdReply?.body || msg.contextInfo?.externalAdReply?.body,
      thumbnailUrl:
        msg.extendedTextMessage?.contextInfo?.externalAdReply?.thumbnailUrl ||
        msg.contextInfo?.externalAdReply?.thumbnailUrl,
      sourceUrl:
        msg.extendedTextMessage?.contextInfo?.externalAdReply?.sourceUrl || msg.contextInfo?.externalAdReply?.sourceUrl,
    };

    return adsMessage;
  }
```

If line numbers or content differ, locate the method with `grep -n "private getAdsMessage" src/api/integrations/chatbot/chatwoot/services/chatwoot.service.ts` and adjust the edit below accordingly.

- [ ] **Step 2: Replace the method body**

Replace the full `getAdsMessage` method (from `private getAdsMessage(msg: any) {` through its closing `}`) with:

```ts
  private getAdsMessage(msg: any) {
    interface AdsMessage {
      title: string;
      body: string;
      thumbnailUrl: string;
      sourceUrl: string;
      sourceId?: string;
      sourceType?: string;
      mediaType?: string;
      mediaUrl?: string;
    }

    const externalAdReply = msg.extendedTextMessage?.contextInfo?.externalAdReply || msg.contextInfo?.externalAdReply;

    const adsMessage: AdsMessage | undefined = {
      title: externalAdReply?.title,
      body: externalAdReply?.body,
      thumbnailUrl: externalAdReply?.thumbnailUrl,
      sourceUrl: externalAdReply?.sourceUrl,
      sourceId: externalAdReply?.sourceId,
      sourceType: externalAdReply?.sourceType,
      mediaType: externalAdReply?.mediaType,
      mediaUrl: externalAdReply?.mediaUrl,
    };

    return adsMessage;
  }
```

This also collapses the previous duplicated `msg.extendedTextMessage?.contextInfo?.externalAdReply || msg.contextInfo?.externalAdReply` fallback into a single `externalAdReply` lookup reused for all 8 fields — same fallback behavior as before (checked per-field originally, but both branches always resolve to the same source object, so hoisting it once is behavior-preserving), just no longer repeated 4 times becoming 8.

- [ ] **Step 3: Typecheck**

```bash
npx tsc --noEmit
```

Expected: no new errors from this file (pre-existing unrelated errors elsewhere, if any, are not this task's concern — only confirm nothing new surfaces referencing `chatwoot.service.ts` near these line numbers).

- [ ] **Step 4: Lint**

```bash
npx eslint --ext .ts src/api/integrations/chatbot/chatwoot/services/chatwoot.service.ts
```

Expected: no new lint errors.

- [ ] **Step 5: Commit**

Do NOT run `git commit` yet — per the Global Constraints, no commits until the user has tested locally and given an explicit "ok". Leave this change staged/unstaged and move to Task 3. (A single combined commit happens in Task 6, after the user validates the full patch end-to-end.)

---

### Task 3: Add `buildReferralAttributes` normalization helper

**Files:**
- Modify: `src/api/integrations/chatbot/chatwoot/services/chatwoot.service.ts` — insert directly after the `getAdsMessage` method from Task 2 (i.e., after its closing `}`, before `private getReactionMessage(msg: any) {`).

**Interfaces:**
- Consumes: `AdsMessage` shape produced by Task 2's `getAdsMessage`.
- Produces: `buildReferralAttributes(adsMessage: AdsMessage): Record<string, string> | undefined` — Task 5 (call site wiring) calls this and passes its result into `sendData`'s new `referral` parameter (Task 4).

- [ ] **Step 1: Insert the new method**

Insert immediately after the `getAdsMessage` method (which now ends with `return adsMessage; }` per Task 2):

```ts
  private buildReferralAttributes(adsMessage: {
    title?: string;
    body?: string;
    thumbnailUrl?: string;
    sourceUrl?: string;
    sourceId?: string;
    sourceType?: string;
    mediaType?: string;
    mediaUrl?: string;
  }) {
    const referral: Record<string, string> = {};

    if (adsMessage.sourceId) referral.source_id = adsMessage.sourceId;
    if (adsMessage.sourceType) referral.source_type = adsMessage.sourceType;
    if (adsMessage.sourceUrl) referral.source_url = adsMessage.sourceUrl;
    if (adsMessage.title) referral.headline = adsMessage.title;
    if (adsMessage.body) referral.body = adsMessage.body;
    if (adsMessage.mediaType) referral.media_type = adsMessage.mediaType;
    if (adsMessage.thumbnailUrl) referral.image_url = adsMessage.thumbnailUrl;

    return Object.keys(referral).length > 0 ? referral : undefined;
  }
```

Note `mediaUrl` is deliberately not read here — per spec40 FR-002, `image_url` is sourced from `thumbnailUrl`, not `mediaUrl` (thumbnailUrl is already proven fetchable as an image by the existing ads-card code; mediaUrl may point at non-image media for video ads).

- [ ] **Step 2: Typecheck**

```bash
npx tsc --noEmit
```

Expected: no new errors.

- [ ] **Step 3: Lint**

```bash
npx eslint --ext .ts src/api/integrations/chatbot/chatwoot/services/chatwoot.service.ts
```

Expected: no new lint errors.

- [ ] **Step 4: Ad-hoc manual verification of the mapping (no test framework available)**

Since this fork has no test runner, verify the pure mapping logic manually with a throwaway script run via `tsx` (already a devDependency, used by `npm run start`), rather than instantiating the full `ChatwootService` class (which requires DB/HTTP providers in its constructor). Create a temporary scratch file — do NOT commit it:

```bash
cat > /tmp/verify-referral-mapping.mjs << 'EOF'
// Standalone copy of buildReferralAttributes logic for manual verification only.
function buildReferralAttributes(adsMessage) {
  const referral = {};
  if (adsMessage.sourceId) referral.source_id = adsMessage.sourceId;
  if (adsMessage.sourceType) referral.source_type = adsMessage.sourceType;
  if (adsMessage.sourceUrl) referral.source_url = adsMessage.sourceUrl;
  if (adsMessage.title) referral.headline = adsMessage.title;
  if (adsMessage.body) referral.body = adsMessage.body;
  if (adsMessage.mediaType) referral.media_type = adsMessage.mediaType;
  if (adsMessage.thumbnailUrl) referral.image_url = adsMessage.thumbnailUrl;
  return Object.keys(referral).length > 0 ? referral : undefined;
}

// Case 1: full payload
console.log('full:', buildReferralAttributes({
  title: 'Ad title', body: 'Ad body', thumbnailUrl: 'https://x/thumb.png',
  sourceUrl: 'https://fb.com/ad', sourceId: '123', sourceType: 'ad',
  mediaType: 'image', mediaUrl: 'https://x/media.png',
}));

// Case 2: partial payload (mediaUrl/mediaType absent, as most real messages will be)
console.log('partial:', buildReferralAttributes({
  title: 'Ad title', body: 'Ad body', thumbnailUrl: 'https://x/thumb.png',
  sourceUrl: 'https://fb.com/ad', sourceId: '123', sourceType: 'ad',
}));

// Case 3: nothing present
console.log('empty:', buildReferralAttributes({}));
EOF
node /tmp/verify-referral-mapping.mjs
```

Expected output:
```
full: {
  source_id: '123',
  source_type: 'ad',
  source_url: 'https://fb.com/ad',
  headline: 'Ad title',
  body: 'Ad body',
  media_type: 'image',
  image_url: 'https://x/thumb.png'
}
partial: {
  source_id: '123',
  source_type: 'ad',
  source_url: 'https://fb.com/ad',
  headline: 'Ad title',
  body: 'Ad body',
  image_url: 'https://x/thumb.png'
}
empty: undefined
```

Confirm `partial` has no `media_type` key (not merely `undefined` — absent) and `image_url` maps from `thumbnailUrl`, not `mediaUrl`. Delete the scratch file after verifying: `rm /tmp/verify-referral-mapping.mjs`.

- [ ] **Step 5**: Leave uncommitted (see Task 2 Step 5 rationale) — move to Task 4.

---

### Task 4: Extend `sendData` with a trailing `referral` param and single-append merge

**Files:**
- Modify: `src/api/integrations/chatbot/chatwoot/services/chatwoot.service.ts:1050-1119`

**Interfaces:**
- Consumes: `referral: Record<string, string> | undefined` from Task 3's `buildReferralAttributes`.
- Produces: `sendData(conversationId, fileStream, fileName, messageType, content?, instance?, messageBody?, sourceId?, quotedMsg?, referral?)` — Task 5's call site passes into this new 10th parameter.

- [ ] **Step 1: Read the current method to confirm line numbers haven't drifted**

```bash
sed -n '1050,1119p' src/api/integrations/chatbot/chatwoot/services/chatwoot.service.ts
```

Expected to match the block shown below (pre-patch). If it differs, locate via `grep -n "private async sendData" src/api/integrations/chatbot/chatwoot/services/chatwoot.service.ts` and adjust.

- [ ] **Step 2: Replace the method**

Replace the full `sendData` method with:

```ts
  private async sendData(
    conversationId: number,
    fileStream: Readable,
    fileName: string,
    messageType: 'incoming' | 'outgoing' | undefined,
    content?: string,
    instance?: InstanceDto,
    messageBody?: any,
    sourceId?: string,
    quotedMsg?: MessageModel,
    referral?: Record<string, string>,
  ) {
    if (sourceId && this.isImportHistoryAvailable()) {
      const messageAlreadySaved = await chatwootImport.getExistingSourceIds([sourceId], conversationId);
      if (messageAlreadySaved) {
        if (messageAlreadySaved.size > 0) {
          this.logger.warn('Message already saved on chatwoot');
          return null;
        }
      }
    }
    const data = new FormData();

    if (content) {
      data.append('content', content);
    }

    data.append('message_type', messageType);

    data.append('attachments[]', fileStream, { filename: fileName });

    const sourceReplyId = quotedMsg?.chatwootMessageId || null;

    let contentAttributes: Record<string, unknown> = {};

    if (messageBody && instance) {
      const replyToIds = await this.getReplyToIds(messageBody, instance);

      if (replyToIds.in_reply_to || replyToIds.in_reply_to_external_id) {
        contentAttributes = { ...contentAttributes, ...replyToIds };
      }
    }

    if (referral) {
      contentAttributes = { ...contentAttributes, referral };
    }

    if (Object.keys(contentAttributes).length > 0) {
      data.append('content_attributes', JSON.stringify(contentAttributes));
    }

    if (sourceReplyId) {
      data.append('source_reply_id', sourceReplyId.toString());
    }

    if (sourceId) {
      data.append('source_id', sourceId);
    }

    const config = {
      method: 'post',
      maxBodyLength: Infinity,
      url: `${this.provider.url}/api/v1/accounts/${this.provider.accountId}/conversations/${conversationId}/messages`,
      headers: {
        api_access_token: this.provider.token,
        ...data.getHeaders(),
      },
      data: data,
    };

    try {
      const { data } = await axios.request(config);

      return data;
    } catch (error) {
      this.logger.error(error);
    }
  }
```

This replaces the old two-branch logic (an isolated `if (replyToIds...) data.append(...)` block, which is exactly the pattern that would have silently clobbered a second independent `append` for `referral`) with a single `contentAttributes` accumulator object that both `replyToIds` and `referral` write into, followed by exactly one `data.append('content_attributes', ...)` call — this is the fix required by spec40's Impact analysis "Duplicate `content_attributes` form field" finding.

- [ ] **Step 3: Typecheck**

```bash
npx tsc --noEmit
```

Expected: no new errors. In particular, confirm the two existing 9-arg call sites (media-in-group-chat branches) still typecheck — they'll implicitly pass `referral: undefined`, which is valid since it's optional.

- [ ] **Step 4: Lint**

```bash
npx eslint --ext .ts src/api/integrations/chatbot/chatwoot/services/chatwoot.service.ts
```

Expected: no new lint errors.

- [ ] **Step 5**: Leave uncommitted — move to Task 5.

---

### Task 5: Wire the ads-message call site to pass `referral`

**Files:**
- Modify: `src/api/integrations/chatbot/chatwoot/services/chatwoot.service.ts:2250-2259` (line numbers as of pre-patch state; will shift slightly after Tasks 2-4's insertions — locate via the anchor text below if so)

**Interfaces:**
- Consumes: `buildReferralAttributes` (Task 3), extended `sendData` signature (Task 4).

- [ ] **Step 1: Locate the call site**

```bash
grep -n "adsMessage.sourceUrl}\`," src/api/integrations/chatbot/chatwoot/services/chatwoot.service.ts
```

This should locate the `sendData` call inside the `if (isAdsMessage) { ... }` block. Confirm the surrounding block matches:

```ts
          const send = await this.sendData(
            getConversation,
            fileStream,
            nameFile,
            messageType,
            `${bodyMessage}\n\n\n**${title}**\n${description}\n${adsMessage.sourceUrl}`,
            instance,
            body,
            'WAID:' + body.key.id,
          );
```

- [ ] **Step 2: Replace the call with the 10-arg version**

```ts
          const send = await this.sendData(
            getConversation,
            fileStream,
            nameFile,
            messageType,
            `${bodyMessage}\n\n\n**${title}**\n${description}\n${adsMessage.sourceUrl}`,
            instance,
            body,
            'WAID:' + body.key.id,
            quotedMsg,
            this.buildReferralAttributes(adsMessage),
          );
```

Note this call site previously omitted `quotedMsg` entirely (relying on it defaulting to `undefined` at position 9). It's now passed explicitly so `referral` can occupy position 10 — `quotedMsg` is in scope here (declared earlier in the same function, already used by the other two `sendData` call sites and by `createMessage` calls in sibling branches), and passing it here fixes a latent inconsistency where ad-reply messages alone never threaded `quotedMsg` — bringing this call site in line with the other two `sendData` call sites' existing behavior, and required to reach the new 10th parameter regardless.

- [ ] **Step 3: Typecheck**

```bash
npx tsc --noEmit
```

Expected: no new errors.

- [ ] **Step 4: Lint**

```bash
npx eslint --ext .ts src/api/integrations/chatbot/chatwoot/services/chatwoot.service.ts
```

Expected: no new lint errors.

- [ ] **Step 5: Full project typecheck (catches any ripple effect across the file)**

```bash
npx tsc --noEmit
```

(Same command as Step 3 — run once more standalone to confirm a clean full-project state after all 4 tasks combined, not just this file in isolation.)

Expected: no errors.

- [ ] **Step 6**: Leave uncommitted — this is the last code change. Move to Task 6.

---

### Task 6: Manual end-to-end validation, then commit

This is the point where the patch is code-complete but unverified against a real Ad Preview click-to-WhatsApp flow — per spec40's Validation section, this fork has no automated test suite, so live manual validation is the acceptance gate, matching how Phase 26's Cloud API investigation was originally validated.

**Files:** none (validation + git operations only)

- [ ] **Step 1: Build the patched image locally**

```bash
cd /home/matias/dev/evolution-api
docker build -t evolution-api:referral-patch-test .
```

(Adjust to whatever local build/run mechanism the user already uses for this fork if a `docker build` isn't the actual local dev flow — confirm with the user before running if unsure, since this step touches their local Docker/Podman environment.)

- [ ] **Step 2: Point a test Evolution instance at the patched image and connect it to a Chatwoot inbox**

Manual — user-driven. Use the same test WhatsApp Business number / Chatwoot inbox pairing already used for Phase 26's Cloud API validation, if available.

- [ ] **Step 3: Trigger a live Click-to-WhatsApp ad flow**

Manual — user clicks a real Meta Ads Manager Ad Preview link, sends the pre-filled message (or replaces it entirely, to also re-confirm spec26's "survives text replacement" thesis holds through this patch), and checks the resulting Chatwoot message.

- [ ] **Step 4: Confirm `content_attributes.referral` on the resulting Chatwoot message**

In Chatwoot, inspect the message's `content_attributes` (e.g., via Rails console: `Message.last.content_attributes['referral']`, or via the API response) and confirm:
- `referral` key is present.
- Field names are exactly `source_id`, `source_type`, `source_url`, `headline`, `body`, `image_url` (and `media_type` if the test ad provides it).
- No `undefined`/`null` noise for fields Meta didn't send.
- The existing ad-card image+caption message still renders identically to pre-patch behavior (purely additive change, no visual regression).

- [ ] **Step 5: STOP — wait for explicit user confirmation before committing**

Per the Global Constraints (and the project's standing CLAUDE.md workflow rule), do not run `git add`/`git commit` until the user has completed Steps 1-4 and explicitly says the patch is validated and ok to commit.

- [ ] **Step 6: Commit (only after explicit user "ok")**

```bash
cd /home/matias/dev/evolution-api
git add src/api/integrations/chatbot/chatwoot/services/chatwoot.service.ts
git status
```

Review the diff scope one more time (`git diff --cached`) — confirm only the 4 intended edits (Tasks 2-5) are staged, nothing incidental.

```bash
git commit -m "feat(chatwoot): capture ad referral attribution in content_attributes"
```

- [ ] **Step 7: Report back**

Confirm the branch name (`feat/chatwoot-referral-attribution`) and commit hash to the user. Do NOT push — pushing to the fork's `origin` remote is a separate, explicit action the user hasn't yet authorized in this conversation.

---

## Self-Review Notes

- **Spec coverage:** FR-001 → Task 2. FR-002 → Task 3. FR-003 → Task 4. FR-004 → Task 5. Validation section → Task 6. All Impact-analysis findings (duplicate-append fix, positional-arg safety, quotedMsg-in-scope) are addressed inline in Tasks 4-5 with explicit rationale. Out-of-scope items (CI/CD, `isAdsMessage` bug, Chatwoot-side changes) are correctly NOT tasked here.
- **Placeholder scan:** no TBD/TODO; every step has literal, runnable commands or complete code blocks; Task 6's docker step includes an explicit caveat rather than presenting an unverified assumption as fact.
- **Type consistency:** `AdsMessage` shape (Task 2) is echoed exactly in `buildReferralAttributes`'s parameter type (Task 3) and in the values passed at the Task 5 call site; `sendData`'s new `referral?: Record<string, string>` parameter type (Task 4) matches `buildReferralAttributes`'s return type (Task 3) exactly.
