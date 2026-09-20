# The object model in one page

> One-line promise: after this page you understand the one idea that makes BioMate cohere —
> everything is a live object you can open, reference, and trust. For everyone.

<!-- Synthesis of already-verified chapters (I.5/I.6/I.7/I.9/I.10/I.4); each claim links to its
     home chapter where it is code-verified in the coverage ledger. -->

## The one idea

In BioMate, the things you work with are not strings in a chat log — they are **objects**. A dataset,
a run, an output, a report, a model, a plan: each has a stable identity, opens the **same way
everywhere**, and carries its own provenance. That is what lets you *audit by clicking* instead of
re-reading.

## The objects

| Object | What it carries | Opens as | Chapter |
|---|---|---|---|
| **Dataset** | identity · ingest quality · lineage · consumers · versions · origin | the dataset object (`/files?file=<id>`), same from a chat chip or the file tree | [I.5](../modules/I05-files-and-dataset-object.md) |
| **Run** | status · parameters · live steps · outputs · findings | the run panel beside the chat; lives in its chat session | [I.6](../modules/I06-running-an-analysis.md) |
| **Step** | inputs → tool+version → outputs · params-by-origin · rendered⇄raw | the full step view | [I.7](../modules/I07-full-step-view-provenance.md) |
| **Output** | bytes · type · size · SHA-256 · the step that made it | an in-app viewer by evidence type | [I.8](../modules/I08-outputs-viewers-interactive.md) |
| **Report** | the after-run record + editable, versioned methods; immutable v0 "run original" | the 3-tab after-run report | [I.9](../modules/I09-reports-and-reproducibility.md) |
| **Model** | identity · evidence · lineage · versions · interface | the model object / registry | [I.10](../modules/I10-models.md) |
| **Plan / hypothesis** | goal + hypothesis a run can cite | a card on the project | [I.4](../modules/I04-projects-instructions-collaboration.md) |

## The three properties every object has

1. **A stable identity.** A dataset's id, a run's id, an output's `runId:s3key` — the same reference
   opens the same object from anywhere (a chat chip, the file tree, a report link).
2. **Provenance.** An output links back to the step that made it; a run to the parameters and inputs
   it ran with; a report to its run (immutable "run original"). Numbers in the findings link to the
   output they came from.
3. **Honest state.** Quality is profiled, not asserted (Good/Watch/Blocked); checksums are real bytes
   (computable on demand); a capability the system can't back is *not* shown (see
   [Appendix E](../appendix/E-coverage-and-roadmap.md)).

## Why it matters

Because objects are live and referenceable, a whole line of work threads together: an **evidence
answer** you save → a **plan** that cites it → a **run** that produces **outputs** → a **report** whose
numbers click back to those outputs → a **dataset** version another run reads. Nothing is a dead
string; each link is something you can open and verify.

> **Tip.** When you see an id, a chip, or a number in BioMate, assume it's clickable — it almost
> always opens the object behind it.

## What's not covered
- A cross-object graph view of an entire project (plan→runs→reports on one screen) is not built yet —
  see [Appendix E](../appendix/E-coverage-and-roadmap.md). Today you traverse object-to-object.
