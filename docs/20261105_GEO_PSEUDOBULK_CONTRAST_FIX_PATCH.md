# GEO pseudobulk nonsense contrasts — review patch (BUG #3)

**Not applied.** Executed R inside a workflow `.nf`; a human applies it and verifies against real
GEO datasets (the observed GSEs). This is the root cause + drop-in fix + expected before/after.

File: `backend/biomni_workflows/nfcore/geo_scrna_pseudobulk/main.nf` (embedded R, lines ~269-358).

## The bug — DE contrasts built from meaningless metadata; "completed" with no real DE
Observed:
- `640b7e9d`: contrast = `Public on Jun 10 2010_vs_Public on May 28 2010` — grouped by GEO
  **publication date**.
- `863429cf`: contrast = `disease state: HNSCC, N+ _vs_ sample type: 15 human cell lines` — two
  **different characteristic keys** (cross-axis).
- Both: run on `data_type=microarray`/`pseudobulk_method=none`, **no DESeq2 output despite status
  "completed"**; gene IDs bare integers, first row all-zeros.

Root cause in `detect_condition_col` (270-286) + ref/target pick (315-324):
- **284:** when no preferred-name column qualifies, it returns `candidate_cols[1]` — the FIRST
  column with 2-5 unique values, **no exclusion of GEO bookkeeping fields**. A "Public on" /
  submission-date column has 2-5 unique dates → selected as the "condition". (housekeeping bug)
- **279:** the preferred list includes `status`, which in a GEO series matrix is the record
  status (Public/…), not biology — it can be picked as the condition.
- **312-324:** `groups <- sort(unique(condition_parsed))`, then ref = most frequent, target =
  first other. When the chosen column is `characteristics_ch1` with **mixed keys per sample**
  ("disease state: …" on some, "sample type: …" on others), ref and target are drawn from
  **different characteristic keys** → a cross-axis contrast. (cross-axis bug)
- No gate rejects a biologically meaningless contrast — it writes `contrasts.csv` and the run
  reports "completed" regardless. (no-validity bug)

## The fix (three parts)

**Part 1 — exclude GEO bookkeeping columns; tighten the preferred list.** Replace
`detect_condition_col` (270-286) with:
```r
    detect_condition_col <- function(meta) {
      n_rows <- nrow(meta)
      # GEO bookkeeping / housekeeping columns are NEVER a biological condition. Selecting
      # one (e.g. "Public on" dates) produced nonsense contrasts like
      # "Public on Jun 10 2010_vs_Public on May 28 2010". Exclude them up front.
      deny <- grepl(paste0("public|submission|last.?update|supplementary|relation|contact|",
                           "platform|organism|molecule|extract|label|data.?processing|scan|",
                           "instrument|library|geo_?accession|series|sample_?id|gsm|gse|",
                           "accession|^status$|date|channel_count|taxid"),
                    names(meta), ignore.case=TRUE)
      candidates <- vapply(seq_along(names(meta)), function(j) {
        if (deny[j]) return(FALSE)
        vals <- unique(trimws(as.character(meta[[j]])))
        n_uniq <- length(vals)
        n_uniq >= 2 && n_uniq <= 5 && n_uniq < n_rows
      }, logical(1))
      # Prefer columns that name a biological factor. (NB: 'status' removed — it is the GEO
      # record status, not a phenotype.)
      pref <- grep(paste0("characteristics|condition|disease|genotype|treatment|phenotype|",
                          "cell.?type|tissue|agent|dose|group"),
                   names(meta), ignore.case=TRUE, value=TRUE)
      pref <- c(intersect("title", names(meta)), pref)
      pref_valid <- pref[pref %in% names(meta)[candidates]]
      if (length(pref_valid) > 0) return(pref_valid[1])
      candidate_cols <- names(meta)[candidates]
      if (length(candidate_cols) > 0) return(candidate_cols[1])
      NULL
    }
```

**Part 2 — reject a cross-axis contrast.** After `chosen_tgt` is determined (after line 324),
add:
```r
    # GEO characteristics encode "key: value". A valid contrast compares two values of the
    # SAME key; "disease state: HNSCC _vs_ sample type: cell lines" mixes two keys and is
    # meaningless. If reference and target carry different keys, fail rather than emit it.
    axis_key <- function(x) if (grepl(":", x)) trimws(sub(":.*$", "", x)) else NA_character_
    rk <- axis_key(chosen_ref); tk <- axis_key(chosen_tgt)
    if (!is.na(rk) && !is.na(tk) && tolower(rk) != tolower(tk)) {
      stop(sprintf(paste0("[GEO] Refusing cross-axis contrast: reference key '%s' != target key ",
                          "'%s'. Provide --condition_col / --reference / --target for a single ",
                          "biological factor."), rk, tk))
    }
```

**Part 3 — fail loudly instead of emitting a "completed" nonsense contrast.** The
`detect_condition_col` NULL path already `stop()`s (294-295). Add one more guard right after
`groups` is computed (after line 313): require ≥2 real groups mapping to ≥1 sample each, and
refuse a contrast where a group label is an obvious date/accession token:
```r
    if (length(groups) < 2) {
      stop(sprintf("[GEO] Column '%s' has <2 usable groups (%s) — no valid two-level factor.",
                   chosen_col, paste(groups, collapse=", ")))
    }
    if (any(grepl("^(public on|submitted|\\d{4}-\\d{2}-\\d{2}|gsm\\d+|gse\\d+)",
                  groups, ignore.case=TRUE))) {
      stop(sprintf("[GEO] Group labels look like bookkeeping, not biology (%s). Provide --condition_col.",
                   paste(groups, collapse=", ")))
    }
```

A `stop()` makes the Nextflow process FAIL — which is correct: a run with no valid contrast must
not report "completed". The after-run UX fix #9 already presents a failed run honestly (no fake
"results"/report).

## Expected before → after
| run | before (bug) | after (fix) |
|---|---|---|
| `640b7e9d` | contrast `Public on Jun 10 2010_vs_Public on May 28 2010`, "completed" | process FAILS: "Group labels look like bookkeeping… provide --condition_col" (date column denied, then guarded) |
| `863429cf` | contrast `disease state: HNSCC, N+ _vs_ sample type: 15 cell lines`, "completed" | process FAILS: "Refusing cross-axis contrast: 'disease state' != 'sample type'" |
| a clean GEO case (e.g. GSE227835 MG/HC) | works | unchanged — real `MG_vs_HC` contrast |

## Secondary (separate, lower priority)
- **scRNA-pseudobulk run on bulk microarray input** (`data_type=microarray`,
  `pseudobulk_method=none`): the routing accepted a microarray series for the scRNA-pseudobulk
  path. Add an input-assay guard (reject/redirect microarray from the pseudobulk path) upstream in
  the GEO routing (`backend/lib/galaxy/ai/ai_assistant.py` GEO fast-path), not in this `.nf`.
- **Bare-integer gene IDs / all-zero first row**: a counts-matrix prep issue independent of the
  contrast; triage once the contrast gate lands (bad contrasts were masking it).

## Verification (human, after applying)
Re-run the two GEO accessions behind `640b7e9d` and `863429cf`: both must now FAIL with the
specific guard message (not "completed" with a nonsense contrast). Re-run a clean two-level GEO
dataset (e.g. GSE227835) and confirm the real `target_vs_reference` contrast is produced and
DESeq2 output is written.
