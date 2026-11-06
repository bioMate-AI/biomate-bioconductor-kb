# UX Test Plan — Master Index & Shared Rubric (Upgrade + V2)

*2026-09-11. A UX-focused test-plan set that walks every module and every function
for BOTH the **Upgrade** and **V2** versions. This complements — does not replace —
the functional use-case plans (`20260909_TESTPLAN_*`). Where those asked "does the
function work?", this set asks "**is the user's journey through it smooth, honest,
and visually correct?**" Other sessions are running publication-replication + UX
tests; these plans are the shared script for the UX half.*

---

## The two versions under test

| Version | What it is | Where to read the intended design | Where the code lives |
|---|---|---|---|
| **Upgrade** | The currently shipped data-centric UI (live on `dev-public.biomate.ai`) — dataset-as-centroid, step deep-view, cold-start dashboard, skippable phases. | `docs/20260908_DATA_CENTRIC_*` + current deployed behavior | `frontend/client/src/components/**` (deployed) |
| **V2** | The `data_centroid_design_v2` spec — adds Models, Design&Generate, all-modalities, search-transparency, editable reports, run-cards-by-domain, panes. | `reference/claude_design/data_centroid_design_v2/spec/*.html` (00–14) + `docs/20260909_V2GAP_*` + `docs/20260911_V2GAP_*_INCREMENT.md` | same tree; V2 pieces flagged in the V2GAP docs |

Every function is tested in **both** columns. When a function exists only in one
version, say so. When V2 changes an Upgrade behavior, add a **Δ (upgrade→v2)** row
stating what changed and whether it improves the journey.

---

## The UX acceptance rubric — every function is scored on these 7 dimensions

A function is **not** "UX-pass" just because it renders. For each function, write
expected + acceptance criteria on all seven:

1. **Journey** — the entry point → the action → the outcome. Is the path discoverable? How many clicks? Does it dead-end? Is the next step obvious?
2. **States & transitions** — idle / loading / running / completed / failed / empty / error. Do transitions animate/update in real time (SSE where applicable)? No stuck spinners; no state that never resolves.
3. **Visual fidelity vs reference** — layout, spacing, alignment, color, typography match the spec/reference. **No "undefined"/blank/NaN in any visible text.** No overflow, no clipped content, no collapsed empty boxes.
4. **Honesty** — honest-empty states ("No entries yet"), never fabricated numbers/figures, never a faked "green", failed runs show a static error (not "Analysis in progress…"). Placeholder vs real data is clearly distinguished.
5. **Interaction & feedback** — hover, focus, click, keyboard nav; disabled states explain *why* (tooltip); destructive/expensive actions confirm; every click gives immediate feedback (toast/spinner/state change).
6. **Responsiveness & a11y** — mobile/narrow layout doesn't break; sensible focus order; aria labels on icon-only controls; contrast adequate.
7. **Cross-version Δ** — how the function differs between Upgrade and V2, and whether V2's change is a UX improvement, regression, or neutral.

### Test-case shape (use for every function)

```
### <Module> › <Function>
- Journey: <entry → steps → outcome>
- Precondition / data setup: <how to reach this state honestly — real API/UI, no mocks>
- Steps: 1… 2… 3…
- Expected UX (per rubric): states=… visual=… honesty=… interaction=… a11y=…
- Acceptance (UX-pass ⇔): <explicit, observable criteria — testids where they exist>
- Upgrade: <behavior/criteria>   V2: <behavior/criteria>   Δ: <what changed>
- Known gap / deferred: <if any, from the V2GAP docs — mark honestly>
```

### Rules (inherited from CLAUDE.md)
- **No mocked APIs** in any live/E2E step — real backend on `dev-public.biomate.ai`, fixture `lifeifei163361@163.com`, bypass `x-e2e-test-token: biomate-e2e-bypass-token-dev-only`.
- **A skip is a fail** — if a case can't be run, say why and treat it as untested, not passed.
- **Audit, don't assert-render** — screenshot each state; compare to the reference; list every deviation.
- Cite the exact **v2 spec section** (00–14) each module maps to.

---

## Cluster assignments (one plan doc each)

| Cluster | Modules / functions | V2 spec §§ | Doc |
|---|---|---|---|
| **A — Entry & Conversation** | Cold-start dashboard (module cards, modality chips, examples), Composer + lane preview ("why this?"), Chat (messages, ClarifyCard, workflow cards, disambiguation, alerts), Sidebar (nav, collapse, history dots) | 00, 06 | `20260911_UXTESTPLAN_A_COLDSTART_COMPOSER_CHAT.md` |
| **B — Run & Execution** | Workflow panel (all states, param strip, QC gate incl. hERG, phase cards, real-time SSE, run-cards-by-domain), Full step view + panes/output previews, After-run report (Outputs/Findings/QC/Methods/Citations/Parameters/Software/Trajectory, editable methods, download) | 07, 08, 12, 13, 14 | `20260911_UXTESTPLAN_B_RUN_STEP_AFTERRUN.md` |
| **C — Data & Models** | Data-analysis surface + datasets (dataset-as-centroid, deep view), Files & the dataset object, Models (Train/House-style/Rounds/Run-a-model/Registry, model object, inference viewers by evidence class, model use cases) | 02, 03, 04, 10 | `20260911_UXTESTPLAN_C_DATA_FILES_MODELS.md` |
| **D — Design, Search & Peripheral** | Search & evidence (retrieval transparency, citation panel, search answers), Design & Generate (all modalities, constraints composer, generation run, candidates, honest gating), Reports, Connectors, Billing/Settings dialogs | 01, 05, 09, 11 | `20260911_UXTESTPLAN_D_SEARCH_DESIGN_PERIPHERAL.md` |

Each cluster doc: cover **every** module/function in scope, on **all 7 rubric dimensions**, for **both** versions, following the test-case shape above. Aim for comprehensiveness over brevity — this is the script other sessions will execute.
