# The full step view & provenance

> One-line promise: after this page you can open any completed or failed step as a single object and see
> exactly what fed it, the parameters it *actually ran with* (and where each value came from), and every
> output — both rendered and as the raw bytes it was derived from. For everyone who needs to trust a
> result before they act on it.

<!-- Every claim here is code-verified (tier C); see coverage-ledger.md "## I.7 The full step view & provenance". No Batch runs fired. -->

## What this is for

A workflow is made of steps. When you want to *trust* a result — before you cite it, hand it to a
regulator, or re-run with a change — you need to see the step as a self-contained object: what went in,
what tool ran, what came out, and which knobs were set to what. BioMate calls this the **full step
view** (`StepDetail`). It answers four questions on one surface
(`frontend/client/src/components/steps/step-detail.tsx:6-18`):

1. **What fed this and what came out** — the provenance row.
2. **The parameters it actually ran with** — each tagged by where its value came from, per-row revertable.
3. **Each output rendered by its evidence class**, with a **rendered ⇄ raw** switch so you can check the
   summary against the bytes it was derived from.
4. **A claim → output hook** — scaffolding so a Findings number can open the exact output that backs it.

It deliberately does **not** re-implement the evidence-typed viewers. The rendered side of each output is
delegated to the shipped `StepOutputPreview` (see I.8), which already resolves image / table / structure /
density / sequence / VCF / text by file type. The full step view adds the *raw* side of the toggle and the
provenance + param-origin framing on top (`step-detail.tsx:11-18`, `:396-405`).

## Where you open it (and where you can't yet)

This is the honest part — read it before you go looking.

| Surface | Reaches the full step view? | Where |
|---|---|---|
| **Live phase view** — a step's **"Details"** button | **Yes** | `PhaseGroupSection` renders a `Details` button on each **completed or failed** step (`nextflow-workflow-viewer.tsx:769-776`); it calls `onOpenFullStepView(step)` → `setFullViewStep(buildStepDetailStep(step))` (`:3162-3173`), which opens `StepDetail` in a dialog (`:3453-3474`). |
| **Live phase view** — a step-output preview's **"Full step view"** button | **Yes** | When you preview a step's file in the running/finished panel, the preview header shows a **"Full step view"** button (`step-output-preview.tsx:863-874`). It is wired only when the panel knows which step owns the file (`nextflow-workflow-viewer.tsx:3428-3430`); the same handler opens `StepDetail`. |
| **After-run report → Outputs tab** | **No** | The Outputs tab opens the rich evidence viewer (`StepOutputPreview`) in an overlay (`AfterRunReport.tsx:1211-1216`), **but it does not pass `onOpenFullStepView`** — so there is no "Full step view" button there, and the param-origin / provenance surface is not reachable from the after-run report. |

> **Pitfall — the full step view lives in the run panel, not the after-run report.** To open a step as an
> object with its param origins, use the run panel's phase list (the **"Details"** button on a completed or
> failed step) *before you close the panel*, or open a step file's preview there and click **"Full step
> view."** The after-run report's Outputs tab gives you the rich viewer and a download, but not the
> param-origin / provenance surface. This is a real wiring gap — see **What's not covered**.

![The step-as-object: provenance row on top, resolved parameters with origin badges below](../assets/i07-1-step-as-object.png)
<!-- CAPTURE route=/ (run panel, a completed run) ; state=open a completed run's phase list, click "Details" on a completed step (e.g. salmon_quant) ; focus=step-detail ; note=show the provenance row (step-provenance) with inputs → tool version → N outputs · duration, and the "Parameters this step actually ran with" list with param-origin badges + the "N not default" count -->

## The provenance row (what fed it → what ran → what came out)

The header carries a single compact chain (`step-detail.tsx:312-337`):

> **ran with** `[input chips]` → `[tool + version]` → `[N outputs]` · `duration`

- **Inputs** — upstream dataset or step names as chips. When the run doesn't report them, it says
  **"upstream step output"** rather than inventing a filename (`:318-322`).
- **Tool + version** — e.g. `salmon 1.10.1`. When the tool isn't reported it says **"tool not reported"**;
  when the version isn't, **"(version n/a)"** (`:324-329`).
- **Outputs** — the count of output files (`:331-333`).
- **Duration** — wall-clock, or **"duration n/a"** when not tracked (`:334-336`).

> **Tip — honest empty states are a feature, not a gap.** The step view is built only from fields the run
> actually reported; anything it doesn't have is shown as "n/a" / "not reported", never guessed
> (`step-detail.tsx:16-18`). In today's live phase data, per-step **tool, version, duration and inputs are
> not tracked**, so those will read "n/a" until the run supplies them — `buildStepDetailStep` deliberately
> **omits** them rather than fabricating (`nextflow-workflow-viewer.tsx:198-215`; locked by
> `nextflow-workflow-viewer.test.tsx:388` "omits tool/toolVersion/duration/inputs — never fabricated").
> The parameters and outputs, which the run *does* report, are shown in full.

## Parameters, tagged by origin

The core of the view: **"Parameters this step actually ran with,"** each row carrying an **origin badge**
and, when it differs from the workflow default, a per-row **revert** link (`step-detail.tsx:417-469`).

Origin is inferred by `resolveStepParams` (`step-detail.tsx:104-138`) and shown by `OriginBadge`
(`:167-182`):

| Badge | Meaning | Colour |
|---|---|---|
| **default** | the value equals the workflow's own default — quiet | grey (`:160`) |
| **inherited** | the value came from a project instruction the backend marked | amber, loud (this is the origin users are most surprised by) (`:162`) |
| **override** | the value differs from the default — changed by hand | blue (`:164`) |
| **unknown** | no default was known for this key, so BioMate does not claim an origin | dashed grey — with a tooltip "origin not reported by the run — shown honestly rather than guessed" (`:168-177`) |

A **"N not default"** count summarises how many parameters were inherited or overridden
(`step-detail.tsx:284`, `:421-426`), so you can see at a glance whether this step ran vanilla or tuned.

> **Tip — read the amber badges first.** A default value is the workflow's own; an *inherited* value came
> from a standing project instruction (see I.4) and is the one most likely to explain a surprising result.
> The view marks it loudly on purpose.

This behaviour is locked by tests: `default` / `override` / `unknown` inference and the `inherited` case
(`step-detail.test.tsx:61-77`), plus the rendered badges and the "1 not default" count
(`step-detail.test.tsx:99-106`).

## Rendered ⇄ raw (check the summary against the bytes)

Each output appears as a tab; selecting one shows it two ways via the **rendered ⇄ raw** toggle
(`step-detail.tsx:362-414`):

- **rendered** (default) — delegated to `StepOutputPreview`, the same evidence-typed viewer used on every
  other surface (`:396-405`). A table renders as a table, a structure with its pLDDT/PAE, a VCF as a track,
  and so on (see I.8).
- **raw** — `RawBytesViewer` fetches the first bytes straight from the step-file endpoint
  (`/api/workflows/runs/:runId/step-file?path=…`) and shows them exactly as the step wrote them
  (`:188-242`). The caption states the contract plainly: *"Raw first: the summary above is derived from
  these bytes, and you can check it"* (`:408-412`).

If the raw bytes can't be read as text (a binary artifact), the raw view says so and offers a direct
download rather than a dead end (`step-detail.tsx:214-228`). Selecting a different output tab resets to
rendered and refetches (`:272-277`, `step-detail.test.tsx:133-140`).

![The rendered ⇄ raw toggle: the same output shown as its evidence-typed viewer and as the raw bytes it was derived from](../assets/i07-2-rendered-raw-toggle.png)
<!-- CAPTURE route=/ (run panel, a completed run) ; state=open a completed step's full step view, select a text/table output (e.g. quant.sf), then click the "raw" toggle ; focus=rendered-raw-toggle ; note=show the toggle group (toggle-rendered / toggle-raw) and the raw-view pane with the "Raw first: the summary above is derived from these bytes" caption -->

The toggle is the load-bearing behaviour the test suite guards: "rendered" delegates to the shipped viewer
with **no** fetch; flipping to "raw" fetches from `/step-file` exactly once and shows the bytes; flipping
back returns the rendered viewer (`step-detail.test.tsx:109-131`).

## Downloads and the claim → output hook

- **Download** — the footer links straight to the artifact, unmodified, via the step-file endpoint with
  `download=1` (`step-detail.tsx:473-486`). "the artifact itself, unmodified."
- **Claim → output hook** — `onOpenOutput(outputId)` fires whenever an output is selected
  (`step-detail.tsx:272-277`), the scaffolding a Findings number will use to open the exact output that
  backs it. It's verified to fire with the selected output's id (`step-detail.test.tsx:142-151`). The
  finding-side wiring that *calls* it is a follow-up (`step-detail.tsx:81-86`) — see What's not covered.

## Re-run from here

`StepDetail` accepts an optional **`onAdjustAndRerun`** prop that, when supplied, renders a **"Re-run from
here"** button in the header (`step-detail.tsx:87-89`, `:301-305`) — the intent being to open the
parameter re-run flow (`StepAdjustModal`) for that step.

> **Pitfall — "Re-run from here" is not wired in the current run panel.** The live phase view opens
> `StepDetail` **without** passing `onAdjustAndRerun` (`nextflow-workflow-viewer.tsx:3465-3471`), so the
> button does not appear there today. Re-running with adjusted parameters is instead available from the
> step row's own **"Rerun"** / adjust affordances in the phase list, which open `StepAdjustModal` directly
> (`nextflow-workflow-viewer.tsx:777-790`, `:3433-3446`), and from the after-run report's "Run again with
> edits" (see I.6). The in-view button is built and ready; it just isn't connected on this surface yet.

## Pitfalls & tips

> **Tip — open it before you close the panel.** The full step view is a run-panel surface. If you've moved
> on to the after-run report, reopen the run's session (see I.6) and use the phase list's **"Details"**
> button to get back to a step's object.

> **Pitfall — "unknown" origin isn't a bug.** A dashed grey **unknown** badge means the run didn't report a
> default to compare against for that key, so BioMate refuses to label it "override." It's being honest,
> not failing (`step-detail.tsx:133-135`, `:167-181`).

> **Tip — raw is the auditor's view.** For a regulatory or reproducibility check, flip to **raw** and
> confirm the rendered summary matches the bytes. That toggle exists precisely so the summary is
> falsifiable, not taken on faith.

## What's not covered

- **The after-run report's Outputs tab does not reach the full step view.** It opens the rich evidence
  viewer (`StepOutputPreview`) but doesn't pass `onOpenFullStepView`, so there is no "Full step view" button
  and no param-origin/provenance surface from the report (`AfterRunReport.tsx:1211-1216`). Reaching the full
  step view after a run means reopening the run panel's phase list. Wiring the button into the report is a
  design decision — Appendix E.
- **"Re-run from here" inside the step view is not connected** on the run-panel surface — `StepDetail` is
  mounted without `onAdjustAndRerun` (`nextflow-workflow-viewer.tsx:3465-3471`). Use the step row's "Rerun"
  / adjust actions or the report's "Run again with edits" instead (I.6). Appendix E.
- **Per-step tool, version, duration and inputs are not tracked** in the live phase data, so the provenance
  row shows "n/a" / "not reported" / "upstream step output" for these until the run supplies them
  (`nextflow-workflow-viewer.tsx:198-215`). This is an honest empty state, not a rendering bug — the fields
  are omitted rather than fabricated. Appendix E.
- **The claim → output hook is scaffolding.** `onOpenOutput` fires correctly, but the Findings-side wiring
  that *calls* it to jump from a summary number to the backing output is a follow-up
  (`step-detail.tsx:81-86`). Appendix E.
- **No Batch runs** were fired to write this page; all claims are code-verified (tier C).

---
_Verification: coverage-ledger.md "## I.7 The full step view & provenance" — all tier C (source-read:
`step-detail.tsx`, `step-detail.test.tsx`, `nextflow-workflow-viewer.tsx`, `step-output-preview.tsx`,
`AfterRunReport.tsx`); no Batch runs fired._
