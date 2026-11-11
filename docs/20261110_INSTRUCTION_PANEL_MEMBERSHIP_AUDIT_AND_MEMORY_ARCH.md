# Instruction panel + membership audit, and BioMate's memory architecture vs the 2026 frontier

**Date:** 2026-11-10. **Scope:** does the project **Instruction panel** (user expectations + feedback) really work end-to-end; is **project membership/invite/rights** fully implemented and tested; and how do these sit against the memory/instruction architectures the frontier labs and open-source stacks shipped in 2026. Two sub-agent code audits + web research; fixes in progress (status at the end).

---

## Part 1 — Instruction panel: is it really working?

The panel (`ProjectInstructionsPage`, mounted at `project-detail.tsx:804`) is **real and mostly wired** — 4 of 5 capabilities reach the LLM.

| Capability | Persists | Injected to LLM | Honored | Verdict |
|---|---|---|---|---|
| **Rules** ("use GRCh38") | ✅ `projects.research_goal` | ✅ **server-side** `routes.ts:7008` → `<project_context>` | ✅ | Works |
| **Skills / experts** | ✅ `project_instruction_settings` | ✅ `buildSkillBlock` (`galaxy-assistant.ts:1787`, real fetch) | ✅ | Works |
| **Output formats** | ✅ `project_instruction_settings.settings.outputRequirements` | ⚠️ **client-threaded only** (`chat-input.tsx`→`appendComposerInstructions` `routes.ts:7045`) | ⚠️ honored in chat reply, **NOT in generated reports** | Half-works |
| **Memory (Notes)** | ✅ `project_knowledge` `user_notes` | ❌ firewalled (`memory-knowledge-filter.ts:11`) | — | Dead **by design** ("Make rule" promotes to Rules) |
| **Corrections (feedback)** | ✅ `correction_log` (`memory-repository.ts:157`) | ✅ `_buildCorrectionContextBlock`→`<long_term_memory>` | ⚠️ **per-user, first-message-only** (`galaxy-assistant.ts:4852`) | Works but leaky |

### Gaps found
1. **[headline] Output formats don't shape deliverables.** The report/methods/findings generators (`routes.ts:1546-1548`, cryo-EM/proteomics generators) are hard-coded templates that never read `outputRequirements`. So "Internal memo: findings-first, ≤200 words, 300dpi greyscale figures" is honored in the chat reply but **ignored by the actual generated reports** — the UI's "write deliverables to these" over-promises.
2. **[structural] Server never reads `project_instruction_settings`.** Output formats + skills reach the model only because the chat composer client-threads them. MCP/programmatic/other paths get Rules (server-loaded) but **not** formats/skills.
3. **[feedback] Corrections are per-user + first-message-only.** `projectId` is stored (`memory-repository.ts:167`) but unused in retrieval, so a correction in Project A surfaces in Project B; and corrections are skipped after the first message of a session.
- Tests: 30/30 relevant unit tests pass, but **none assert the server-side injection chain end-to-end** (saved setting → final system prompt).

---

## Part 2 — Membership / invite / rights: fully implemented & tested

**Verdict: complete, server-enforced with the correct 404-not-403 convention, nothing lost.** 49/49 offline tests pass + a comprehensive Playwright e2e suite (PM/PS/AUTHZ/TW) exists (needs live dev to run). All in `frontend/server/project-routes.ts`.

- **Roles:** owner (= project owner) / editor / viewer (`project_members.role`). Helpers `_getUserRole`/`_isOwnerOrMember`/`_isOwnerOrEditor` gate **every** `/api/projects*` endpoint; the UI `canEdit` flag is cosmetic and backed by real server checks.
- **Rights (summary):** view/list → any member (404 to non-members); edit instructions/files/settings, add files, save outputs → editor+; invite/role-change/remove/transfer/share-link/archive/delete → owner only. Collaboration ops are additionally Team-plan gated (`blockedByCollaborationTier`).
- **Invite — both paths work:** existing user → added to `project_members` (idempotent re-role); new email → `project_share_tokens` + `/join/<token>` email → register (honors `next`) → auto-accept → member added. e2e TW1-11 covers the full new-user journey.
- **Nothing dead-wired:** git history + `docs/20260720_PROJECT_COLLAB_AUDIT_AND_FIXES.md` match the code; a past "files owner-only" regression is already fixed to member-readable.

### Gaps
1. **[fixed this session]** New-email invite reused an existing share token and ignored the requested role (invite as editor → joins as viewer, email mismatch). Fixed: the invite now updates the token role to match (`project-routes.ts:1146-1158`), mirroring `/share-link`. *Residual:* a single per-project token means concurrent pending invites share one role — per-invite tokens would be the fuller fix (not done).
2. **[design decision — open]** A **viewer can launch workflow runs** (billed to their own account; writing outputs back is editor-gated). If viewers should be read-only on compute, the launch path (`routes.ts:6961`) needs an `_isOwnerOrEditor` gate. Left for product decision.
- Test-hygiene debt: the membership e2e harnesses register throwaway accounts, against CLAUDE.md's single-fixture rule (functionality fine).

---

## Part 3 — BioMate vs the 2026 memory/instruction frontier

**Memory architectures (2026):**
- **Anthropic / Claude** — 4 layers (transcripts → memory notes → representations/wikis → **injected context**) + **"dreaming"**: offline consolidation between sessions (merge duplicates, drop stale), memory-as-files, editable. (Formalized Nov 6 2026.)
- **Google — Vertex AI Memory Bank** — Sessions → Memory Extraction (Gemini) → Consolidation (resolve contradictions) → Semantic Search (Vector Search).
- **Open-source** — Mem0 (vector+graph dual store; inclusion/exclusion + depth; **user-scoped vs agent-scoped** memory), Letta/MemGPT (self-editing in-context core blocks), Zep/Graphiti (temporal knowledge graph).

**Instruction panels (2026):** Claude Projects, ChatGPT custom instructions, Gemini Gems all inject instructions **server-side, on every path, from the first response**, and **layer** account-profile → project → chat-style.

**Where BioMate sits — the map is good, the execution is where it diverges:**
| Layer | BioMate today |
|---|---|
| Transcripts | `chat_sessions.messages` |
| Memory notes | `project_knowledge`, corrections (P2), episodes (P1) |
| Representations | `project_context`, standing recent-runs block, consolidated episode "patterns" |
| Injected context ("universe model") | standing blocks incl. **always-on runs** (added 2026-11-09) |
| Consolidation ("dreaming") | `consolidateEpisodes` → patterns, nightly cron (`routes.ts:13636`) |
| Instruction panel (= Claude Project instructions / Gems) | rules ✅ / skills ✅ / formats ⚠️ / memory (firewalled) / corrections ⚠️ |

**Divergences (what the frontier does that BioMate should):**
1. **Standing server-side injection on every path.** The frontier injects instructions server-side universally; BioMate client-threads formats/skills and first-message-gates corrections. → the fixes below.
2. **Instruction layering** — account/profile → project → chat-style. BioMate is project-only; an account-level preference layer + per-chat style would complete it.
3. **Inclusion/exclusion + depth** (Mem0) — say *what to remember and what to exclude*. Relevant to the clinical/PHI context (exclude certain data from memory).
4. **Consolidation scope** — BioMate consolidates *episodes* only; Anthropic's dreaming consolidates the whole memory and builds a per-project "memory wiki" (layer 3).
5. **Semantic memory retrieval** — Google/Mem0 fetch memories by vector similarity to the query; confirm whether BioMate's cross-session recall is embedding-based or keyword.

---

## Part 4 — Fixes (this session)

| # | Fix | Status |
|---|---|---|
| 4 | Membership invite role-reuse bug | ✅ done (`project-routes.ts:1146-1158`; 18/18 tests) |
| 1 | Output formats honored in server-side report/deliverable composition | ⏳ in progress |
| 2 | Server reads `project_instruction_settings` itself → formats/skills on every path | ⏳ in progress (with #1) |
| 3 | Corrections: standing context (not first-message) + project-scoped | ⏳ in progress |

All four are the same architectural thread the frontier points at: **make user expectations (instructions) + feedback (corrections) standing, server-side, universe context** — the same treatment just applied to runs.

## Part 5 — Recommended next (not yet done)
- Instruction **layering** (account-profile layer + per-chat style).
- **Inclusion/exclusion + depth** controls in the panel (PHI-aware).
- Extend **consolidation** beyond episodes (corrections/prefs dedup + a per-project memory wiki).
- Verify/upgrade **semantic retrieval** of memories.
- Decide membership Gap #2 (viewer run access).
