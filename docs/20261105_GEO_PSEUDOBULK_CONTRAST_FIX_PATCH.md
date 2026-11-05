# GEO pseudobulk nonsense contrasts — STRUCTURAL review patch (BUG #3)

**Not applied.** Executed R inside a workflow `.nf`; a human applies it and verifies against real
GEO datasets. **This is the structural (root-cause) version** — it replaces the earlier
heuristic draft (keyword denylist + fail-loud guards) and ALSO removes a pre-existing
dataset-specific hardcode. See "Why structural, not heuristic" below.

File: `backend/biomni_workflows/nfcore/geo_scrna_pseudobulk/main.nf` (embedded R, lines ~269-325).

## The bug — DE contrasts from meaningless metadata; "completed" with no real DE
- `640b7e9d`: contrast `Public on Jun 10 2010_vs_Public on May 28 2010` (grouped by GEO
  **publication date** — the `status` column's values).
- `863429cf`: contrast `disease state: HNSCC, N+ _vs_ sample type: 15 human cell lines` (two
  **different characteristic keys** — cross-axis).
- Both emit `contrasts.csv` and report "completed" over a biologically meaningless comparison.

## Root cause
1. `detect_condition_col` (270-286) falls back to the FIRST column with 2-5 unique values with no
   exclusion of GEO bookkeeping — so the `status` column (`"Public on <date>"`) gets picked.
2. The chosen column's **raw values are used as groups** (312). GEO `characteristics_ch1*` values
   are `key: value`; when one column carries **mixed keys** across samples, ref/target are drawn
   from different keys → cross-axis contrast.
3. No gate rejects a meaningless contrast; it writes it and reports "completed".
4. **Pre-existing hardcode (301-310):** a `# For GSE227835` branch that string-matches
   `MG|myasthenia|AChR|…` to collapse one specific study's titles into MG/HC. Dataset-specific
   logic in a "general" workflow — the exact anti-pattern CLAUDE.md forbids.

## Why structural, not heuristic
A keyword denylist/allowlist only patches symptoms (a new bookkeeping column, or a biological
column the list doesn't know, slips through). The **root cause** is that the code never parses
GEO's `key: value` structure and never guarantees ref/target share one key. The fix below parses
characteristics structurally so **cross-axis contrasts become impossible by construction** (we
pick ONE key and contrast its values), and drops the GSE227835 hardcode (the disease-state
characteristic yields its values generically). Two keyword lists remain, but neither is a
correctness gate: `is_bookkeeping` only EXCLUDES obvious non-biology, and `bio_rx` only RANKS
among already-valid candidates when choosing a default.

## The fix — replace lines 269-325 (`# ── 4. Auto-detect …` through the `# Determine reference and target` block, INCLUDING the 301-310 GSE227835 hardcode) with:
```r
    # ── 4. Choose a biological factor from GEO characteristics ────────────────
    # GEO series-matrix pData encodes annotations as "key: value" in characteristics_ch1*
    # columns. A valid DE contrast compares two VALUES of ONE key. Parse structurally
    # instead of guessing a column by name or hardcoding a study: for each candidate
    # column split "key: value", REQUIRE every sample to share the same key (a mixed-key
    # column is cross-axis → skip it), and keep the per-sample VALUE as the factor. This
    # makes the "disease state vs sample type" cross-axis contrast impossible and removes
    # the need for the old per-study (GSE227835 MG/HC) special-case.

    # Columns that are never a biological factor (GEO bookkeeping). EXCLUSION only —
    # correctness does not depend on this list being complete; it just avoids obvious noise
    # (e.g. the `status` column that holds "Public on <date>").
    is_bookkeeping <- function(col) grepl(paste0(
      "geo_accession|^status$|submission|last.?update|supplementary|relation|contact|",
      "^type$|platform|organism|molecule|extract|label|data.?processing|scan|instrument|",
      "library|channel|taxid|^date|.*_protocol$|description|^source_name"), col, ignore.case=TRUE)

    # Parse a column into list(key, values): split "key: value" and require ONE key across
    # all samples; return NULL for a mixed-key (cross-axis) column. A non key:value column
    # is used raw, keyed by its own name.
    parse_factor <- function(col_vals) {
      v <- trimws(as.character(col_vals))
      kv <- nzchar(v) & grepl(":", v)
      if (length(v) > 0 && all(kv)) {
        keys <- trimws(sub(":.*$", "", v))
        if (length(unique(keys)) != 1L) return(NULL)        # mixed keys → reject (cross-axis)
        return(list(key = unique(keys)[1], values = trimws(sub("^[^:]*:", "", v))))
      }
      list(key = NA_character_, values = v)
    }

    looks_like_bookkeeping_value <- function(groups) any(grepl(
      "^(public on|submitted|\\d{4}-\\d{2}-\\d{2}|gsm\\d+|gse\\d+)", groups, ignore.case=TRUE))

    n_rows <- nrow(sample_meta)
    candidates <- list()
    for (col in names(sample_meta)) {
      if (is_bookkeeping(col)) next
      pf <- parse_factor(sample_meta[[col]]); if (is.null(pf)) next
      uq <- unique(pf$values[nzchar(pf$values) & !is.na(pf$values)])
      if (length(uq) >= 2 && length(uq) <= 5 && length(uq) < n_rows &&
          !looks_like_bookkeeping_value(uq)) {
        candidates[[length(candidates)+1]] <- list(col=col, key=pf$key, values=pf$values, n_levels=length(uq))
      }
    }

    # Honor explicit --condition_col; else prefer a named biological key; else first clean
    # candidate. bio_rx only RANKS valid candidates — it is not a correctness gate.
    pick <- NULL
    if (nchar(cond_col) > 0) {
      for (c in candidates) if (identical(c$col, cond_col) || identical(c$key, cond_col)) pick <- c
      if (is.null(pick)) stop(sprintf("[GEO] --condition_col '%s' is not a clean 2-5 level factor.", cond_col))
    }
    if (is.null(pick) && length(candidates) > 0) {
      bio_rx <- "disease|condition|genotype|treatment|phenotype|cell.?type|tissue|agent|dose|group|subtype|stage|response|^sex$|age.?group"
      labels <- vapply(candidates, function(c) paste(c$col, c$key), "")
      ord <- order(-as.integer(grepl(bio_rx, labels, ignore.case=TRUE)),
                   vapply(candidates, function(c) c$n_levels, 0L))
      pick <- candidates[[ord[1]]]
    }
    if (is.null(pick)) {
      stop("[GEO] No clean biological two-level factor in the metadata. Provide --condition_col / --reference / --target.")
    }
    chosen_col <- pick$col
    condition_parsed <- pick$values
    cat(sprintf("[GEO] Factor: column='%s' key='%s' (%d levels)\\n",
                pick$col, ifelse(is.na(pick$key), "<raw>", pick$key), pick$n_levels))

    groups <- sort(unique(condition_parsed[nzchar(condition_parsed) & !is.na(condition_parsed)]))
    if (length(groups) < 2) {
      stop(sprintf("[GEO] Factor '%s' has <2 usable groups (%s).", chosen_col, paste(groups, collapse=", ")))
    }
    cat(sprintf("[GEO] Condition groups: %s\\n", paste(groups, collapse=", ")))

    # Determine reference and target — both are values of the SAME key, so no cross-axis.
    chosen_ref <- if (nchar(ref_group) > 0 && ref_group %in% groups) ref_group else {
      tbl <- sort(table(condition_parsed), decreasing=TRUE); names(tbl)[1]   # most frequent ≈ control
    }
    chosen_tgt <- if (nchar(tgt_group) > 0 && tgt_group %in% groups && tgt_group != chosen_ref) tgt_group else {
      go <- groups[groups != chosen_ref]; if (length(go) > 0) go[1] else groups[length(groups)]
    }
    cat(sprintf("[GEO] Contrast: %s (target) vs %s (reference) [key=%s]\\n",
                chosen_tgt, chosen_ref, ifelse(is.na(pick$key), chosen_col, pick$key)))
```
Everything downstream (the `sample_metadata.csv` / `counts_matrix.csv` / `contrasts.csv` writes at
327-358) is unchanged — it already consumes `condition_parsed`, `chosen_ref`, `chosen_tgt`,
`chosen_col`.

## Expected before → after
| run | before | after |
|---|---|---|
| `640b7e9d` | `Public on …_vs_Public on …`, "completed" | `status` column is bookkeeping-excluded; date-valued factors rejected → process FAILS "No clean biological two-level factor… provide --condition_col" |
| `863429cf` | `disease state: … _vs_ sample type: …`, "completed" | mixed-key column returns NULL in `parse_factor` → never a candidate; a single-key disease-state factor is used, or FAILS loudly |
| GSE227835 (MG/HC) | worked via the hardcoded branch | works generically: the disease-state characteristic yields its two values (e.g. `AChR+ MG` vs `healthy control`) — no study-specific code |

## Secondary (separate, lower priority)
- **scRNA-pseudobulk on bulk microarray input** (`data_type=microarray`): add an input-assay guard
  upstream in the GEO routing (`ai_assistant.py` GEO fast-path), not in this `.nf`.
- **Bare-integer gene IDs / all-zero first row**: a counts-matrix prep issue, independent of the
  contrast; triage once the contrast gate lands.

## Verification (human, after applying)
1. Re-run `640b7e9d` and `863429cf`: both FAIL with a specific `[GEO]` message (not "completed").
2. Re-run GSE227835: real `AChR+ MG`-vs-`healthy control` (or equivalent) contrast, DESeq2 output
   written — WITHOUT the removed GSE227835 branch.
3. Re-run one more clean 2-level GEO study to confirm the structural parse generalizes.
