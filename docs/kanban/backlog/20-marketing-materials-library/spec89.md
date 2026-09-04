# Phase 89: Marketing Materials Library

**Status**: placeholder — pending brainstorm session
**Depends on**: none identified yet — likely a new subsystem, not an extension of an existing one.

## Quick Preview

Identified during a market-landscape brainstorm (2026-09-04). The operator shared a reference
screenshot from another CRM ("Prospect") showing a "Materiais de Marketing" module: a searchable,
filterable grid of campaign assets (image/video cards for WhatsApp and social media), organized
by campaign, with favoriting, suggested materials, and download/like actions — meant to be shared
directly with a lead during a conversation.

Operator's own framing: "foge um pouco do escopo de um CRM, mas quem sabe" — this is explicitly
the least-defined and most speculative of the items captured in this brainstorm session, worth
revisiting scope before committing to a full design.

Open questions for the brainstorm:
- Is this in scope for the Kanban/CRM module at all, or a separate module entirely? Worth
  settling before any data-model or UI work.
- Storage: a new `Custom::MarketingMaterial`-style model with Active Storage attachments, or
  something simpler (e.g. just links to externally-hosted assets)?
- Where does sharing happen — a picker inside the conversation composer, or launched from the
  opportunity panel?
- Curation/approval workflow — who uploads and organizes materials (admin-only?), and is
  campaign-based grouping/tagging needed to mirror the reference screenshot?
