# Feature Specification: Scout RAG Knowledge Search (Embeddings)

**Feature Branch**: `048-scout-rag-knowledge-search`

**Created**: 2026-08-21

**Status**: Draft

**Input**: User description: "@docs/kanban/ciclo 10/scout/07-rag-knowledge-search/spec67.md" (Phase 07 of the Scout AI engine — see master doc `docs/kanban/backlog/scout/spec60.md` §7.2, §11). Depends on Phase 01 (`ScoutKnowledgeSource`), Phase 02 (native tool invocation pattern), and Phase 06 (`ScoutAccountConfig`).

## Clarifications

### Session 2026-08-21

- Q: Should the `search_knowledge_base` retrieval tool include source metadata (such as source title or URL) alongside the question and answer text in results returned to the Scout? → A: Return only the question and answer text without source metadata to minimize token overhead.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - On-Demand Knowledge Retrieval During Conversations (Priority: P1)

When a lead asks questions about products, services, pricing, business hours, or policies during a conversation with a Scout, the Scout dynamically searches its knowledge base for relevant facts and uses the retrieved answers in its response, instead of loading the entire knowledge base text into every message prompt.

**Why this priority**: Core value of the feature. Full-text prompt injection consumes excessive context tokens on every turn and limits knowledge base scale. Dynamic retrieval reduces token costs and ensures accurate, scalable answers.

**Independent Test**: Can be fully tested by creating a knowledge source for a Scout, sending a user question related to that knowledge, and verifying that the Scout retrieves the top matching Q&A pairs and responds accurately.

**Acceptance Scenarios**:

1. **Given** a Scout with indexed knowledge sources, **When** a lead asks a question relevant to that knowledge, **Then** the Scout queries the knowledge base and receives the top relevant question-and-answer pairs to construct its reply.
2. **Given** a Scout with indexed knowledge sources, **When** a lead sends a greeting or message unrelated to knowledge base content, **Then** the Scout answers normally without unnecessary knowledge tool calls.
3. **Given** multiple Scouts in the same account or different accounts, **When** a Scout executes a knowledge search, **Then** only knowledge items associated with that specific Scout and account are returned.
4. **Given** a conversational turn, **When** the system builds the base instructions for the Scout, **Then** raw knowledge source contents are not injected into the base prompt text.

---

### User Story 2 - Automated Knowledge Ingestion and Indexing (Priority: P1)

When an administrator or agent creates or updates a knowledge source (a web URL, an uploaded document, or a direct FAQ), the system automatically extracts the content, synthesizes structured question-and-answer pairs (for documents/URLs), and computes searchable vector embeddings without requiring manual indexing actions.

**Why this priority**: Essential pipeline for making knowledge searchable. Without automatic ingestion and vector indexing, the on-demand search tool has no data to query.

**Independent Test**: Can be fully tested by creating a new URL, document, or FAQ knowledge source and confirming that structured Q&A pairs and search vectors are automatically generated and ready for retrieval.

**Acceptance Scenarios**:

1. **Given** a newly added web URL or document knowledge source, **When** content extraction completes, **Then** the system synthesizes question-and-answer pairs and generates searchable vector embeddings for each pair.
2. **Given** a newly added direct FAQ knowledge source, **When** saved, **Then** the system directly indexes the question and answer with a vector embedding without running an extra synthesis step.
3. **Given** a large document or web page, **When** generating Q&A pairs, **Then** the content is safely truncated to a defined maximum size before synthesis to ensure reliable processing.

---

### User Story 3 - Clean Reprocessing and Stale Data Eviction (Priority: P2)

When an administrator reprocesses an existing knowledge source (e.g., after website updates or revising source files), all previous indexed Q&A entries and embeddings for that source are purged and regenerated from scratch, ensuring no stale, conflicting, or duplicate answers remain.

**Why this priority**: Prevents hallucination and conflicting information caused by lingering outdated knowledge embeddings after content updates.

**Independent Test**: Can be fully tested by modifying/reprocessing an existing knowledge source and verifying that old Q&A embeddings are replaced by the new entries with no residual duplicate records.

**Acceptance Scenarios**:

1. **Given** a knowledge source with existing indexed embeddings, **When** the user triggers reprocessing, **Then** the previous embeddings for that source are completely removed before new embeddings are created.
2. **Given** a deleted knowledge source, **When** removal is confirmed, **Then** all associated indexed embeddings are immediately deleted from the search index.

---

### User Story 4 - Graceful Degradation for Unsupported Embedding Providers (Priority: P2)

When an account is configured with an AI provider that does not offer a native embedding capability (such as Anthropic), the Scout continues to handle qualification and standard conversation tools normally, gracefully omitting the knowledge search tool without crashes, runtime exceptions, or broken message handling.

**Why this priority**: Ensures system stability and uninterrupted conversational workflows across all supported LLM providers.

**Independent Test**: Can be fully tested by configuring an account with Anthropic credentials, sending messages to a Scout, and verifying that the Scout operates without errors while the knowledge search tool is safely omitted.

**Acceptance Scenarios**:

1. **Given** an account configured with an LLM provider that does not support embeddings, **When** a Scout initializes its available tools, **Then** the knowledge search tool is not registered and the Scout operates normally.
2. **Given** an account configured with an embedding-capable provider (e.g., Gemini or OpenAI), **When** a Scout initializes its available tools, **Then** the knowledge search tool is registered and ready for execution.

---

### Edge Cases

- **Empty Search Results**: When a lead asks a question that matches no indexed knowledge pairs, the search returns an empty result set and the Scout relies on its standard persona instructions rather than failing.
- **Provider API Outage during Embedding**: If the embedding provider fails during asynchronous indexing, the affected knowledge items remain marked appropriately so they can be reprocessed without corrupting existing ready items.
- **Provider API Outage during Search Tool Execution**: If the embedding service fails while executing the live search tool, the error is handled cleanly and the conversation is directed according to the standard fail-safe policy.
- **Oversized Text Content**: When raw extracted text exceeds processing limits, the ingestion service truncates the input safely rather than exceeding token quotas or causing request timeouts.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST extract and index knowledge sources (FAQs, documents, and web URLs) into semantic question-and-answer pairs for conversational retrieval.
- **FR-002**: System MUST automatically generate question-and-answer pairs from document and URL knowledge sources upon successful content extraction.
- **FR-003**: System MUST directly index structured FAQ knowledge sources without requiring additional AI synthesis.
- **FR-004**: System MUST generate and store vector embeddings for all question-and-answer entries using the account's configured LLM provider.
- **FR-005**: System MUST provide an on-demand semantic search capability allowing the Scout to query the knowledge base during live conversations.
- **FR-006**: System MUST scope knowledge search results strictly to the knowledge sources belonging to the active Scout and Account.
- **FR-007**: System MUST return the top relevant question-and-answer matches (up to 5) containing strictly question and answer text without source metadata to minimize conversational token overhead.
- **FR-008**: System MUST eliminate full-content knowledge base dumping into the base conversational system prompt.
- **FR-009**: System MUST instruct the Scout to use semantic knowledge search when answering user inquiries requiring knowledge base facts.
- **FR-010**: System MUST automatically delete existing indexed embeddings when a knowledge source is reprocessed or deleted, preventing duplicate or outdated search results.
- **FR-011**: System MUST detect whether the account's configured AI provider supports vector embeddings.
- **FR-012**: System MUST gracefully disable the knowledge search tool for accounts configured with providers lacking embedding capabilities, without disrupting conversational flow or raising runtime errors.
- **FR-013**: System MUST truncate oversized source content to a safe processing limit prior to question-and-answer synthesis.

### Key Entities *(include if feature involves data)*

- **Knowledge Embedding / Indexed Q&A**: Represents an individual searchable question-and-answer pair derived from a knowledge source, containing query text, content snippet, and associated vector embedding.
- **Knowledge Source**: The parent entity representing an external URL, uploaded document, or custom FAQ belonging to a Scout.
- **Scout Agent**: The conversational AI agent that performs semantic search queries against its indexed knowledge sources.
- **Account LLM Configuration**: The account-level provider configuration that determines the embedding model and API credentials.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: System prompt token consumption per conversational turn for Scouts with active knowledge bases decreases by at least 60% compared to full-content prompt injection.
- **SC-002**: 100% of newly added or reprocessed knowledge sources (FAQs, documents, URLs) are automatically indexed and searchable within 30 seconds of content extraction under normal operating conditions.
- **SC-003**: 100% of semantic searches retrieve only knowledge pairs strictly scoped to the active Scout and Account.
- **SC-004**: Reprocessing a modified knowledge source results in zero stale or duplicate Q&A pairs in search results.
- **SC-005**: 100% of conversations on accounts using non-embedding providers continue to execute qualification workflows without interruption or unhandled errors.

## Assumptions

- Account-level LLM configuration (Phase 06) is active and provides valid provider credentials.
- Existing knowledge source models (`ScoutKnowledgeSource`), UI components, and raw text extraction jobs remain unchanged.
- Gemini and OpenAI accounts support native vector embeddings; Anthropic accounts do not provide embeddings and will omit the tool without secondary keys.
- PDF and document parsing extracts raw text in a single pass; multi-page provider-native upload streaming is out of scope for v1.
- Both English and Portuguese translations will be maintained synchronously for any user-facing text or notifications.
