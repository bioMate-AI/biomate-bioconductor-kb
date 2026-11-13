# Models Module — Committee Convenience Audit (2026-11-12)

Founder: "the Models module in the sidebar is still not convenient to use — audit it
with committee first." Committee = 3 independent LLMs via OpenRouter (gpt-6.1,
gemini-4, claude-opus-5.5), each given the current code of `models-panel.tsx`,
`training-launcher.tsx`, `run-pretrained.tsx`, `model-object.tsx`, `training-logic.ts`
plus the product requirements. Findings below are ranked by **cross-model consensus**
(how many of the three independently raised it) then severity. Two live founder
examples (NVIDIA label; "train a potency predictor on our CSV") are folded in.

## Consensus HIGH — all three models raised these

1. **The model detail view is a read-only dead end.** `ModelsPanel` renders
   `<ModelObjectLoader>` with only `onBack`/`onOpenModel`; `onUseInRun`, `onSupersede`,
   `onOpenRun`, `onOpenData`, `onCompareVersion` are all `undefined`, so "Use in a run",
   "Supersede/retrain", lineage links, and version-compare all disappear. You can open a
   model and do **nothing** with it — the only exit is Back.
   → Wire the handlers: Use-in-run (switch to Library, preselect this model in
   RunPretrained), Supersede (switch to Train, prefill from lineage), Open-run/Open-data
   (deep links), Compare-version.

2. **Every run link ejects to the chat page with no per-run deep link.**
   `openRunManager()` (`training-logic.ts`) does `window.location.assign('/')` — a full
   reload into all-chats Run Manager, no specific run, destroying the Models page and any
   in-flight form/result. For a Boltz-2 fold it's the ONLY way to see the result — a
   disguised "check in chat" punt.
   → Inline run-detail drawer in the panel (useRunStatus + logs/outputs/metrics); if a
   Run-Manager link stays, make it SPA nav with a real `/?run=<id>` deep link.

3. **Training still excludes sequences and images (not "general ML/DL").**
   `fileKind()` only recognizes csv/tsv/txt/jsonl/parquet, h5ad, pdb/cif. FASTA/FASTQ and
   image datasets fall to `'other'` → `availableModelTypes()` returns `[]` → user is
   blocked. (The current build DOES already have LLM fine-tune + scRNA/protein diffusion —
   the "only table + molecule" screenshots are stale — but sequence/image are still walls.)
   → Extend `FileKind`/`fileKind()` + `availableModelTypes()` + `SPEC_FIELDS` for sequence
   and image modalities.

4. **"Run a model" can't pick the model and misrepresents what actually runs.**
   `pickModelId()` silently grabs the first catalog entry matching a coarse domain; for
   **structure** it displays `bionemo:boltz2`/OpenFold2 as the model while `run()` ignores
   it and always launches Boltz-2 on **our AWS Batch** — so the row shows "NVIDIA-hosted"
   (founder's LLMStillNividia screenshot) for a model BioMate runs itself.
   → Explicit model `<select>` filtered by domain; honest origin badge (Boltz-2 → BioMate
   AWS Batch; OpenFold2/Evo2 → NVIDIA-hosted); `onUseInRun` preselects the exact model.

5. **Opening a model unmounts the whole panel and loses state.** `if (openModelId) return
   <ModelObjectLoader/>` replaces the tabs; launcher form, pasted inference input, and
   in-flight run cards (all local `useState`) are wiped; `openModelId` isn't in the URL, so
   browser Back leaves `/models` and models can't be linked.
   → Render the detail as an overlay/side-sheet (or keep Tabs mounted with `hidden`); put
   `model`/`tab` in the route; persist in-flight runIds.

## Consensus HIGH/MEDIUM — two of three

6. **No in-panel file upload + active-project desync.** The launcher only lists existing
   project files (no upload/dropzone), and its `project` state initializes once and never
   syncs with the sidebar's active project (and `ModelsPanel` defaults `project` to the
   literal `'Project'`). A user with a local CSV must leave /models to upload.
   → Inline upload next to the dataset select; `useEffect` sync on active-project change;
   `useActiveProjectSafe()` when the prop is omitted.

7. **Column roles are free-text or require exact hardcoded header names.** LLM SFT
   prompt/response columns are free-text (violates "dropdown of real columns"); DPO/GRPO
   vanish unless the file has literal `prompt`/`chosen`/`rejected` columns. This is the
   same anti-pattern behind the founder's "Train a potency predictor on our CSV" example,
   where the chat demanded a free-text `target_col`.
   → Add a `'column'` SpecField kind rendered as a `<select>` over the real profiled
   columns; let any column be mapped.

8. **No model-adaptation / fine-tune-a-generative-model flow.** "Adapt the generative
   model to our chemical series" has no matching surface and routes to an empty workflow.
   → Add a generative-model adaptation flow (base-model + series-data select, run,
   register); route adaptation intent to it.

## MEDIUM / LOW

9. **DMTA Rounds (分子学习) is read-only** — no start/advance/stop/accept-proposal controls.
10. **English leaks into the zh UI** — ModelObject is almost entirely hardcoded English
    (breadcrumbs, badges, gate verdicts, buttons, paragraphs); domain IDs/`family`/`status`/
    `verdict` render raw next to localized copy.
11. **Fold reports non-`failed` terminal states (cancelled/error/interrupted) as "done."**
12. **Training-runs list goes stale** — not invalidated when a run reaches a terminal state,
    so it shows "running" and hides the Register button until a manual refresh.

## Cross-surface (chat routing, not the panel) — from the CSV example

A clear training request in chat ("Train a potency predictor on our in-house assay data" +
`bace_assays.csv`) is routed to a **generic parameterized workflow** that cannot read the
CSV, then asks the user to describe the columns by hand and demands a free-text `target_col`.
Training intent from chat should route to the Models training flow (auto-profile the CSV,
present real columns as a dropdown), not a param-only workflow. This lives in the chat/
assistant routing, separate from the panel, and pairs with finding #7.

## Proposed fix sequence (bounded, test-first, reversible)

P0 (dead-ends → working, highest convenience/line): #1 wire ModelObject actions, #2 inline
run-detail (kill the `/` eject), #4 explicit model select + honest Boltz-2/AWS-Batch origin
(closes the NVIDIA-label defect).
P1: #5 overlay + URL state, #6 in-panel upload + project sync, #7 column-role dropdowns
(closes the free-text target_col defect).
P2: #3 sequence/image modalities, #8 adaptation flow, #9 Rounds controls, #10 zh localization,
#11/#12 terminal-state + staleness correctness.

Each lands behind its own tests (component render + the touched logic), gate-green, synced,
and verified on dev — same loop as the panel fixes.

## Shipped (verified live on dev, build-info 74ecc46ede)

- **Round A — full ML/DL set in the launcher** (`adceabff9f`): added `tabular_diffusion`
  (TabDDPM/TabSyn), which was in backend `MODEL_TYPES` but missing from the panel; offer
  `ludwig_llm` by free-text content (not unconditionally); a `'column'` SpecField kind
  renders instruction/output/target as dropdowns of real columns (closes #7 + the
  free-text `target_col` chat example); DPO/GRPO kept honest to the backend's literal
  prompt/chosen/rejected columns.
- **Round B — model detail no longer a dead end** (`03010f6ec6`): wired `onUseInRun`
  (→ Library tab + preselect the model's domain in RunPretrained via a new `initialModelId`),
  `onSupersede` (→ Train tab), `onOpenRun` (→ Run Manager); made the Tabs controlled so
  programmatic navigation works. (Finding #1.)
- **Round C — honest Boltz-2 origin** (`e31189251f`): backend `origin_override='aws_batch'`
  for Boltz-2 (it folds on BioMate's own Batch), so the catalog + run section read
  "BioMate compute" instead of "NVIDIA-hosted"; run section shows the model name + origin
  badge + localized domain badge. (Finding #4 / the LLMStillNividia screenshot.)

### Still open (Round D+)
#6 in-panel upload + active-project sync · #2 inline run-detail (needs a non-chat-overlapping
deep link) · #5 overlay + URL state for the detail view · #9 DMTA Rounds controls ·
#10 ModelObject zh localization · #11 fold terminal-state correctness · #12 training-runs
staleness · the chat-routing fix (training intent → Models flow). Backend column-mapping for
DPO/GRPO (let any columns map) is the follow-up noted in Round A.
