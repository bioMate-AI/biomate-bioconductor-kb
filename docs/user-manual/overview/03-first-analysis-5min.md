# Your first analysis in 5 minutes

> One-line promise: after this page you've seen the whole loop once — goal → workflow → result — so
> the rest of the book is just detail. For everyone.

<!-- Walks the real run lifecycle (I.6). Each step links to its home chapter. -->

You don't need to install anything or learn workflow names. Here is the whole loop, once.

## 1. Open a new chat and describe your goal
On the [cold start](../modules/I01-getting-started-cold-start.md), type what you want in plain language:

> "Differential expression between treated and control on this counts matrix, then GO enrichment."

As you type, the router restates what it heard as a **lane** (Instant vs Cloud) and a **domain**. This
one is a **Cloud** workflow (a validated pipeline). See the [two lanes](00-what-is-biomate.md).

## 2. Attach your data
In the [composer](../modules/I02-composer-talking-to-biomate.md), attach your file (drag-drop, the
Database browser, or a public accession like `GSE49712`). BioMate profiles it at ingest and shows a
[quality read](../modules/I05-files-and-dataset-object.md) — Good / Watch / Blocked — *before* anything
runs, so you fix problems early.

## 3. Review the workflow card, then Confirm & Run
BioMate proposes a workflow card; the [run panel](../modules/I06-running-an-analysis.md) opens beside
the chat with parameters pre-filled from your request. Adjust a parameter if you want (or just tell
BioMate in chat). Click **Confirm & run workflow**. It launches on the cloud.

## 4. Watch it run
The panel streams live: the overall badge goes `running`, and each phase card flips
`pending → running → completed`. If a [QC gate](../appendix/C-qc-gate-reference.md) trips, you'll see
it (and, in some domains, an auto-loop that remediates and re-runs).

## 5. Read the result
When it completes, the panel becomes the [after-run report](../modules/I09-reports-and-reproducibility.md):
- **Summary** — the headline findings; each number links to the [output](../modules/I08-outputs-viewers-interactive.md) it came from.
- **Outputs** — every file, opened in an in-app viewer (table, volcano/heatmap figure, …).
- **Reproducibility record** — parameters, software, citations, and checksums; download the whole thing.

That's the loop. The run lives in this chat session — reopen it any time.

## Where to go next
- Your domain chapter (e.g. [transcriptomics](../domains/transcriptomics.md)) for the use cases and how
  to read each output.
- [The object model](01-object-model.md) to understand how datasets, runs, outputs and reports link.
- [Appendix D](../appendix/D-troubleshooting-routing.md) for common "correct-but-surprising" moments.

> **Tip.** Not sure it's a big run? Ask an Instant question first ("what's the evidence for X?") — you
> get a cited answer in seconds, in the same conversation, before committing to a cloud run.
