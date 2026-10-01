# Proteomics Search — Social / External Drafts (FOR REVIEW — do not post)

**Date:** 2026-10-01
**Status:** DRAFTS ONLY. Nothing here has been or should be posted. The user reviews + posts.
**Source of truth for every number:** `docs/20261001_PROTEOMICS_SEARCH_BENCHMARK_REPORT.md`
(→ `docs/20260929_PROTEOMICS_SEARCH_SPEED_RECALL.md`).

**Honesty rules applied (per project norms):**
- Lead with the OUTCOME, not the plumbing. No infra-stack disclosure (no AWS/Batch/Nextflow/executor,
  no "we wired together X").
- Numbers are always in benchmark context ("on a standard human-proteome benchmark with
  entrapment-based FDR control, X× faster and Y% more peptide IDs at 1% FDR"), never a bare "222% more".
- Light credibility tag only: built on best-in-class open methods. We do **not** claim BioMate invented
  Sage or Mokapot.
- No "first / best / unmatched" — the field has strong prior art (fragment-indexed engines + ML
  rescoring are established; see the survey).
- Every post carries the one-line honest caveat (relative gains on a specific benchmark).

---

## A. LinkedIn / X short post (primary)

> **Faster proteomics search — without trading away the IDs.**
>
> On a standard human-proteome search benchmark (one ProteomeTools run, ~65k spectra, ~20k proteins),
> BioMate ran the identification end-to-end **~5× faster** than a conventional brute-force engine — and
> at the same time found **~2.6× more peptides at 1% FDR**.
>
> The part we care about most: the FDR is **entrapment-validated**, not just target-decoy. We mixed
> known-false (shuffled) sequences into the database and confirmed the measured false-match rate stayed
> at or below the claimed 1%. More IDs only count if they're real — here they are.
>
> It runs on best-in-class open methods (a fragment-indexed search engine + semi-supervised rescoring),
> composed so you get the speed *and* the recall in one pass, on real data, through the same path you'd
> use for an actual project.
>
> Caveat worth stating plainly: these are relative gains measured on one standard benchmark — we're
> extending it to more datasets next.

---

## B. X / Twitter (tighter, thread-safe single tweet)

> Proteomics DB search, same data, 1% FDR: ~5× faster end-to-end AND ~2.6× more peptides than a
> brute-force baseline — with the FDR validated by entrapment (known-false sequences), so the extra IDs
> are real, not inflated. Built on best-in-class open methods. (Relative gains, one standard benchmark.)

---

## C. Longer blog variant

### Title: Finding more peptides, faster — and proving the "more" is real

**The short version.** On a standard human-proteome search benchmark, BioMate's proteomics
identification runs **about 5× faster end-to-end** than a conventional brute-force engine and finds
**about 2.6× more peptides at 1% false-discovery rate (FDR)** on the same data — and we verified that
the extra identifications are genuine, not an artifact of loose statistics.

**Why "faster" and "more" usually fight each other.** A shotgun-proteomics run produces tens of
thousands of MS/MS spectra, each of which has to be matched against a large space of candidate
peptides. The classic tension: make the search space bigger to find more, and the search gets both
slower and less able to tell true matches from the growing cloud of look-alikes. Most tools win one
axis at the cost of the other.

**What we measured.** We ran a single, controlled benchmark — one real ProteomeTools DDA run (about
65,000 spectra) searched against the reviewed human proteome (about 20,000 proteins) — three ways, with
everything held identical: the same database, the same tolerances and modifications, the same hardware,
and crucially **the same downstream FDR scorer applied to every run** so no tool grades its own
homework.

- A conventional brute-force engine as the baseline.
- A fragment-indexed engine, which organizes the candidate space so each spectrum looks up its
  plausible matches instead of scanning everything. This is where the speed comes from.
- The fragment-indexed engine plus semi-supervised rescoring, which sharpens the line between true
  matches and decoys. This is where the extra identifications come from.

**The result.** The indexed engine finished the search end-to-end about 5× faster while matching or
improving recall. Adding rescoring on top brought the total to roughly 2.6× more peptides (and ~3.2×
more peptide-spectrum matches) at 1% FDR versus the baseline.

**The honesty check — this is the part that matters.** Recent proteomics literature (2025) has shown
that machine-learning rescoring can *under-report* FDR, meaning some of the headline "more IDs" numbers
you see elsewhere may partly reflect loosened statistics rather than real discoveries. So we didn't
just trust the standard target-decoy estimate. We built an **entrapment** database — a matched set of
known-false sequences shuffled from real proteins — and measured how often a match landed on one of
them. Across the operating point, the measured false-match rate stayed **at or below** the claimed 1%.
The additional identifications are real.

**What it's built on, and what we claim.** This runs on best-in-class open methods — a fragment-indexed
search engine and a semi-supervised rescorer from the proteomics community. We didn't invent those; our
contribution is composing them into one dependable, benchmarked path and validating the result with
entrapment-based FDR so you can trust the numbers. Fragment indexing and ML rescoring are established
techniques with meaningful prior art; the value here is the honest, reproducible head-to-head and the
fact that it runs on real data in the same place you'd do real work.

**Honest scope.** These are **relative** gains measured on a **single standard benchmark**. The
absolute identification counts are modest by design (a synthetic peptide pool searched against the full
human proteome, with a conservative 1:1 entrapment, deliberately keeps the bar strict). The ratios are
strong and internally consistent; we're extending the benchmark to additional datasets — a longer
gradient, an immunopeptidomics set, a defined species mixture — to show they generalize. We'll publish
those as we run them.

---

## D. One-line caveat footnote (attach to any post)

> Figures are relative gains measured on one standard human-proteome search benchmark (ProteomeTools,
> ~65k spectra) at 1% FDR with entrapment-based validation; broader datasets are in progress. Built on
> best-in-class open methods (a fragment-indexed engine + semi-supervised rescoring).

---

## Number check (for the reviewer — every figure traces to the report)

| Phrase used | Exact measured figure | Source |
|---|---|---|
| "~5× faster end-to-end" | 153.1 s → ~29 s = 5.3× | report §3.1 |
| "~2.6× more peptides at 1% FDR" | 73 → 191 peptides = +162% (×2.6) | report §3 / §3.1 |
| "~3.2× more PSMs" | 260 → 836 PSMs = +222% (×3.2) | report §3 / §3.1 |
| "measured false-match rate at or below 1%" | Sage+Mokapot FMR 0.24% @1%FDR (all arms ≤ nominal at 1%) | report §4 |
| "one ProteomeTools run, ~65k spectra, ~20k proteins" | PXD010595, 65,521 scans, 20,431 target proteins | report §2 |
| "best-in-class open methods (fragment-indexed engine + semi-supervised rescoring)" | Sage (MIT) + Mokapot (Apache-2.0) | report §2.4 |

Deliberately NOT said anywhere (would over-claim or break the honesty rules): no "first/best/unmatched";
no infra stack named; no "BioMate invented Sage/Mokapot"; no bare percentage without benchmark context;
no absolute-count hype (counts are modest and the drafts avoid implying otherwise).
</content>
