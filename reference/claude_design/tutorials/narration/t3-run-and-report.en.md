# T3 Running a workflow and reading the report — narration (EN)

## Step 1 — Title · run it, then read it

Most real analysis isn't one step — it's a pipeline, a sequence of steps that each take an input, do something, and pass the result on. A workflow in BioMate is one of these pipelines, already tested and connected for you. You describe your goal in plain English, attach your data, and it runs the whole thing on cloud computers and hands back one report. We'll follow a real, completed run — predicting ADMET safety properties for three familiar molecules: aspirin, caffeine, and ibuprofen — from set-up, to live progress, to the three-tab report.

---

## Step 2 — The ideas you need first

Five words make the whole report readable. A workflow is the ready-made pipeline you run but don't assemble. It's organised into phases and steps — big stages, each made of individual tools, where every step takes an input and produces an output. Parameters are the settings it runs with, shown with sensible defaults before anything starts. A QC gate is an automatic mid-run check that never silently passes a failed result. And the after-run report is what you get back, in three tabs. One honest caveat: tested means each step uses an established, published method — not that the result is clinically proven.

---

## Step 3 — Step 1 · set up and confirm

You asked for ADMET in plain English, and BioMate picked the validated workflow and opened its panel on the right. Before any compute is spent, you review the set-up. This run takes parameters only — no data files to bind, though other workflows would attach your FASTQ, CSV, or SMILES file right here. The required parameters are already filled in: the three SMILES strings, and the ADMET model. You can also see where results will be kept and that you have permission to run it. This is your one chance to check or change everything first. When it looks right, you press Confirm and Run — and nothing happens until you do.

---

## Step 4 — Step 2 · watch it run

Now the Phases tab shows the run live. Each step moves from pending, to running, to completed, in real time — here the first step, Admet Infer Shard, is running, while the second is still pending. Below them are the QC gates this run enforces, and they're worth reading: these are cardiac-safety thresholds — the hERG safety margin, qNet risk, APD90 prolongation, and more. They are the limits the run checks against. If a result crosses one, BioMate flags it with the measured value next to the threshold — it never silently continues past a failed check. You can pause or stop at any time, and keep chatting while it runs in the background.

---

## Step 5 — Step 3 · completed, and the honesty feature

The run completes — a green Completed badge, and the three-tab After-run report opens on Summary. Normally, Summary turns the outputs into a short, readable account, with every number pulled straight from the output files. But look closely at this run. Its output files could not be read — so instead of inventing a plausible-sounding summary, BioMate withholds the findings and says exactly that. The findings are generated directly from the real outputs, so if it can't read them, it won't claim them. The "RUN ORIGINAL" badge marks the unedited record; anything you edit is saved alongside it, never overwriting the original. This withholding is the feature, not a bug — a result you can't trust is worse than no result.

---

## Step 6 — Step 4 · outputs, every file by step

Here's the key point: the findings were withheld, but the files were always served. The Outputs tab lists every file the run produced, grouped by the step that made it — six files here, each labelled with its type. There's the ADMET results, a toxicity report, QC metrics, a PK summary, a text table, and a versions file recording the exact software. Each is filed under the step that produced it, so you can trace the pipeline end to end. You can view or download any single file, grab all six as a ZIP, open them in a Jupyter notebook, or save them to a project. This is the raw truth behind any summary — and it's yours to read directly.

---

## Step 7 — Step 5 · the reproducibility record

The third tab is the reproducibility record — the complete audit trail, kept together, with nothing hidden or discarded. It pins down the exact run: a unique run id, its status, and the created and completed timestamps. It lists the parameters and every output with its type and size, and expandable sections hold the methods, the software versions, the citations, the QC report, and the full decision trajectory. Checksums are computed on demand — the SHA-256 fingerprints show a dash until you click Compute checksums, so anyone can verify they have the exact same file. And one click downloads the whole record as JSON. This is what makes a result defensible — for a paper, a patent, or a regulatory submission.

---

## Step 8 — Closing · the habit at a glance

So the habit is simple and the same every time. Ask in plain English, check the settings, and Confirm and Run. Watch the phases go from pending to running to completed, and mind the QC gates. Then read the three tabs: trust the Summary, or trust that it's honestly withheld; read the Outputs file by file; and download the reproducibility record. Set-up, live progress, outputs, and the record are all validated on this real run. The Summary's findings were withheld here because the outputs couldn't be read — reported honestly, not fabricated. That traceability is what turns "the run finished" into a result you can actually explain and justify.

---
