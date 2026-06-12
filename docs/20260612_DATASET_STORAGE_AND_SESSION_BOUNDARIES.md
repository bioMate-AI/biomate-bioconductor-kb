# Dataset storage, size boundaries, and session-isolation policy (2026-06-12)

This document answers two related questions raised during the
2026-06-12 chat-context audit:

1. *What datasets does BioMate actually store, how large can they be,
   and do we need a boundary?*
2. *We've previously seen the inverse bug — context from an old session
   bleeding into a new one. What's the policy and how do we enforce it?*

---

## 1. What we store (and what we don't)

**Critical architectural point: the dataset bytes themselves are
never in BioMate's Postgres.** The file lives in Galaxy's filesystem,
S3, or the upload dir. The DB only holds a *reference* — a handful of
bytes per dataset.

| Layer | What's stored | Practical size | Hard limit |
|---|---|---|---|
| **Actual file bytes** (FASTQ, BAM, MRC, …) | Galaxy / S3 — not our DB | 1 MB – 100 GB+ | Galaxy / S3 quotas |
| `chat_sessions.datasets` jsonb | `{id, name, type, file_path}` per attached dataset | ~150 B × N datasets | jsonb max ~1 GB; ~1 MB before perf hurts |
| `chat_sessions.messages` jsonb | All turn text incl. `[Galaxy dataset: name (id: uuid)]` reference blocks (text only) | ~5–15 KB per turn × N turns | same |
| Galaxy fetch I proposed for cold-refresh (§3 below) | id, name, file_type, state, create_time | ~100 B × ≤20 datasets ≈ 2 KB | bounded by `limit=20` |
| `<session_datasets>` prompt block | Same ~100 B × ≤32 entries | ~2.5 KB | hard cap already enforced (`galaxy-assistant.ts`) |

The size of the underlying file **does not matter**. A 10 GB FASTQ and
a 10 KB CSV both produce the same ~150 B reference row. The Galaxy
`id` is the handle; the bytes stay where they were.

## 2. Size boundaries — current state and recommended additions

| Boundary | Current state | Recommendation |
|---|---|---|
| `<session_datasets>` prompt block | ✅ 32-entry cap, ~2.5 KB | keep as-is |
| Chat history payload to LLM | ✅ 16 KB cap (`selectChatHistoryUnderBudget`) | keep as-is |
| Compression trigger | ✅ 70% / 80% of 200K tokens, UUIDs preserved verbatim | keep as-is |
| `chat_sessions.datasets` jsonb | ⚠ No cap | Add `MAX_DATASETS_PER_SESSION = 100`; drop oldest reference on overflow. File in Galaxy stays. |
| `chat_sessions.messages` jsonb | ⚠ No cap | Auto-evict pre-compression turns once their content is folded into a summary row. Today an un-pruned 200-turn chat can reach 2-3 MB. |
| Cold-refresh fetch from Galaxy | ⏳ Proposed §3 | Hard `limit=20&state=ok`; cache 30 s per session. |

Recommended boundary additions are low-priority (Postgres handles 2-3
MB jsonb fine; we just don't want a runaway pathological case).

## 3. Cross-session context isolation — the inverse bug

### Past incident pattern

We previously hit the opposite of the wjunlin@HKU bug: a *new* chat
session pulled context from an *old* one — datasets, prior runs,
parameter assumptions — and produced confused answers
(*"continuing your RNA-seq analysis on TCGA-LUAD"* when the user just
asked about cryo-EM in a fresh session).

### Policy (this is the design rule going forward)

> **Datasets and context flow across sessions only when they share a
> project. They never flow across projects.**

Project is the isolation boundary. Within a project, sessions can
borrow attached datasets, learned procedures, episodic memory, and
project knowledge — that's the whole point of having projects. Across
projects, every chat starts blank.

### Implications for the Galaxy-history cold-refresh fetch

My earlier sketch of the cold-refresh fetch was **wrong**: I proposed
pulling the user's last 20 datasets from their entire Galaxy history.
That would re-introduce exactly the inverse bug: a cryo-EM session
suddenly sees the wjunlin GSE22055 microarray files from last week.

The corrected design:

| Source of truth | When to use |
|---|---|
| `chat_sessions.datasets` for THIS sessionId | Always — datasets explicitly attached this conversation |
| Other sessions' `chat_sessions.datasets` **within the same `projectId`** | When client sends empty `previousMessages` AND the current session has no datasets attached yet (cold refresh recovery) — limit to the most recent 20 |
| Galaxy history (user-scoped, no project filter) | **Never as default.** Only when the LLM explicitly proposes "you have X in your Galaxy history — should I use it?" and the user confirms. |

Implementation outline (separate PR):

```ts
// Cold-refresh recovery, project-scoped:
async function recoverProjectDatasets(projectId: string, currentSessionId: string) {
  const rows = await pool.query(`
    SELECT DISTINCT ON (d->>'id') d->>'id' AS id, d->>'name' AS name,
                                  d->>'type' AS type, last_activity
    FROM chat_sessions cs, jsonb_array_elements(cs.datasets) d
    WHERE cs.project_id = $1
      AND cs.session_id != $2
      AND last_activity > NOW() - INTERVAL '14 days'
    ORDER BY d->>'id', last_activity DESC
    LIMIT 20
  `, [projectId, currentSessionId]);
  return rows.rows;
}
```

(Requires `chat_sessions.project_id` column to actually be populated —
follow-on once Q4 has been writing for a few hours.)

### Implications for memory-integration

The same rule already governs `findMatchingProcedures`,
`getSimilarEpisodes`, and `projectMemory.knowledge` — they're all
gated on `context.projectId`. That gating was correct from day one;
it just never delivered because no `projectId` was ever set (Q4 fix,
2026-06-12). With Q4 live, the project boundary is now real.

### `<session_datasets>` prompt block — must label the source

When the cold-refresh recovery surfaces datasets from a *different*
session in the same project, the prompt block must label them as such
so the LLM doesn't claim the user just attached them:

```
<session_datasets>
Datasets attached to this conversation:
  - clinical_gse22055.csv | id=… | type=csv

Datasets from earlier sessions in the same project (recovered after refresh):
  - gse22055_expression.csv | id=… | type=csv

If the user refers to "the dataset" and the chat is new, ask which
one — do NOT assume.
</session_datasets>
```

This is the same idea as Q1 (preserved-dataset-attachments header in
compression summaries): explicit provenance instead of opaque
recombination.

## 4. Decisions logged

1. **Dataset size has no DB implication.** Files stay where they are;
   we move 150-byte references. No per-file size cap needed in our
   layer.
2. **Add three small jsonb caps** in a future cleanup PR:
   - `chat_sessions.datasets`: 100-entry cap, drop oldest on overflow.
   - `chat_sessions.messages`: post-compression eviction once a summary
     row exists for the older turns.
   - Cold-refresh Galaxy fetch: hard `limit=20`, cache 30 s.
3. **Cross-session dataset reuse is project-scoped, never user-scoped.**
   Memory-integration's project gating already enforces this for
   procedures / episodes / knowledge. The same rule applies to the
   cold-refresh dataset recovery path.
4. **The cold-refresh fetch I proposed in the previous turn is
   superseded by this document.** The corrected version queries
   `chat_sessions` within the same `projectId`, not the user's full
   Galaxy history.

---

## See also

- `docs/20260610_REAL_USER_FULL_CHAT_LOGS.md` — wjunlin@HKU root incident.
- `docs/20260610_CHAT_CONTEXT_AUDIT_4_QUESTIONS.md` — Q1/Q2/Q3/Q4 audit.
- `docs/20260611_CHAT_FIXES_USECASE_AUDIT.md` — UC-A/B/C/E live evidence.
- `frontend/server/canonical-chain-steps.ts`, `chat-history-selector.ts`,
  `context-compressor.ts`, `memory-repository.ts` — the code these
  decisions govern.
