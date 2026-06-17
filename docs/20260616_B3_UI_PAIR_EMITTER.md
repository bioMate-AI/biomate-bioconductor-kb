# B3 UI affordance — IND editor records DPO pairs on AI-edits — 2026-06-16 PM

Closes the very last unwired step in the B3 product chain. The recorder
+ Node route + CLI verb shipped earlier this session (see
`20260616_B3_UPSTREAM_PAIR_RECORDER.md`); this turn adds the UI that
actually calls it during normal customer use.

## The wire

`frontend/client/src/components/regulatory-document-editor.tsx` —
the TipTap-based §2.6 IND prose editor that opens in the right panel
after the assembler finishes. It already tracked AI-vs-human spans via
the Highlight mark (paragraphs the assembler wrote carry a
`<mark data-ai-generated="true">` wrapper; user edits strip the mark).

This commit hooks the AI→edited transition: when a block's mark
disappears AND the text differs from the snapshot taken at load, the
editor POSTs

```jsonc
{
  "chosen":   "<the user's new text>",
  "rejected": "<the original AI text>",
  "section_type": "2.6.4",                // §X.Y.Z of the nearest heading
  "prompt": "IND §2.6.4 for ACME-001"
}
```

to `/api/regulatory_llm/pairs`. The Node route (see
`regulatory-training-routes.ts`) stamps `org_id` from `req.user`
server-side — the browser cannot supply it (anti-spoofing).

## Design choices

| Choice | Why |
|---|---|
| **1.2 s debounce** | A multi-keystroke edit coalesces into one POST. Without this we'd flood the JSONL with partial-prose rows. |
| **Per-block dedup** | After a block fires once, further edits to the same block don't re-fire until the document reloads. The first edit is the signal; rolling micro-edits are noise. |
| **Live-DOM baseline, not raw-HTML** | TipTap normalises whitespace and unknown attributes. If we used the pre-mount HTML extract as the "original," every block would look "edited" the moment the editor mounts. Snapshot is taken via `requestAnimationFrame(snapshotLiveBaseline)` after `setContent`. Caught by the regression-guard test. |
| **`section_type` by DOM walk** | The flush walks blocks in DOM order, tracking the most recent heading whose text contains a §X.Y.Z id. Same edit emits `2.6.4` under PK, `2.6.1` under pharmacology — the worker / compiler gets clean section attribution for free. |
| **`recordPairFn` injectable** | The default impl `fetch(/api/regulatory_llm/pairs, credentials:"include")`. Tests pass a vi.fn() to assert payloads without touching network. |
| **`recordEditPairs` opt-out** | Default true (production). Demos / e2e fixtures pass `false` to keep the JSONL clean. |
| **Gated off when `isLocked`** | Post-eSig the document is frozen; no edits ⇒ no recording. |
| **Errors swallowed** | Recording is best-effort feedback. A 4xx / network failure must NEVER disrupt the editor — the user is doing real regulatory writing. |

## Regression-guard test caught a real bug

The `does NOT spuriously emit pairs on mount (no edits yet)` test
failed on first run. Investigation revealed TipTap normalises the
HTML during parse, so `extractBlockTexts(raw HTML)` !==
`block.textContent` after mount. Without the fix, every existing AI
paragraph would have been recorded as "edited" within ~1.2 s of the
editor loading. The fix (snapshot from live DOM via
`requestAnimationFrame`) is the correct architecture, not a
test-fixture hack. The test now pins it.

## Test gates

| Gate | Result |
|---|---|
| `regulatory-document-editor.test.tsx` (3 tests: mount-doesn't-emit + recordEditPairs=false + isLocked=true) | **3/3 ✅** |
| `frontend tsc --noEmit -p .` | **clean ✅** |
| Backend B3 suites (pair recorder + org_fewshot + ind_org_rag, 27 tests) | **27/27 ✅** |
| Backend drug_discovery full pytest (152 tests, ignoring pre-existing 15 errors in `test_modal_app_structure.py`) | **152 ✅** |

## Full 14-step loop now wired end-to-end with NO manual seeding

```
[user] edits an AI paragraph in the §2.6 editor
   ↓ (1.2 s debounce, per-block dedup)
[react] flushEditPairs → recordPairFn → fetch POST /api/regulatory_llm/pairs
   ↓
[node] regulatory-training-routes.ts
        • authenticateToken
        • orgFor(req.user) server-side stamp
        • runCliWithStdin(["record_pair", userId, orgId], JSON body)
   ↓
[python CLI] regulatory_training_jobs_cli.record_pair verb
   ↓
[recorder] regulatory_pair_recorder.record_pair
        • _safe_org sanitisation
        • validate + cap 8K chars per side
        • append JSONL row to data/regulatory_training/dpo/customer_pairs.jsonl
        • flush + fsync
   ↓
   (time passes; customer accumulates pairs)
   ↓
[user] clicks "Re-train on my edits" in Settings → Advanced
   ↓
POST /api/regulatory_llm/training_jobs
   ↓
[worker] regulatory_training_worker tick
        • mode=prompt_rules → org_rule_compiler (chosen-vs-rejected citation diff)
        • mode=few_shot_index → org_fewshot_index (token-Jaccard exemplars)
   ↓
[artifacts] data/regulatory_training/{org_rules,org_fewshot}/<org>.{yaml,jsonl}
   ↓
   (next IND assembly request)
   ↓
POST /api/drug-discovery/<campaign>/ind-assembly
   ↓
[node] wildcard proxy auto-injects body.org_id from req.user.organization
   ↓
[python] INDSectionAssembler.assemble(..., org_id=...)
   ↓
[14 call sites] _llm_narrative(..., org_id=ctx['org_id'])
   ↓
_build_rag_context emits to the LLM context:
   • Region-specific style rules (B2)
   • Org-specific rules from <org>.yaml (B3a)
   • Top-K few-shot exemplars from <org>.jsonl (B3b)
   • Skills-DB narrative patterns
   • OSP PBPK benchmark context
   ↓
[LLM] reads the customer's house-style rules AND examples
       from their own accepted edits → adapted output prose
```

## Files added / changed (this commit)

| File | Change |
|---|---|
| `frontend/client/src/components/regulatory-document-editor.tsx` | Added `recordEditPairs` / `recordPairFn` props, `flushEditPairs` callback with 1.2 s debounce + per-block dedup, live-DOM baseline snapshot, `indexBlocksAndSections` DOM-walking helper, `defaultRecordPairFn` fetch impl |
| `frontend/client/src/components/regulatory-document-editor.test.tsx` | NEW — 3 vitest cases (no-spurious-emit-on-mount, recordEditPairs=false gates, isLocked=true gates) |
| `docs/20260616_B3_UI_PAIR_EMITTER.md` | NEW — this file |

## Git tip after this commit

```
origin/integration/next-phase: 170b48b94
```

## What remains (all gated, none blocking)

- EMA EPAR scraper — external blocker (URL scheme moved)
- n=30/task cross-judge expansion (~$90)
- Re-eval with all wires hot (~$30) — would verify
  `region_adaptation` lifts above 0.388 with the rule-pack RAG live
- B5 per-section model routing — needs n=30/task harness witness
- `post_train_lora` real GPU worker — gated on harness witness + GPU
  budget

The customer-feedback → adapted-prose loop now runs end-to-end with
**zero manual JSONL seeding**.
