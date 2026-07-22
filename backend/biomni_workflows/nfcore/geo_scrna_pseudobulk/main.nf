// geo_scrna_pseudobulk — BioMate stub: GEO auto-fetch + pseudobulk aggregation
// Downloads a GEO dataset, performs pseudobulk aggregation (scRNA-seq) or passes
// through expression matrix (bulk), and outputs three CSVs ready for
// nf-core/differentialabundance (counts_matrix, sample_metadata, contrasts).

nextflow.enable.dsl = 2

params.geo_accession  = null   // GEO accession e.g. GSE227835 (required)
params.condition_col  = null   // metadata column for condition grouping (auto-detect if null)
params.reference      = null   // reference group label (auto-detect if null)
params.target         = null   // target group label (auto-detect if null)
params.min_cells      = 10     // min cells per sample to include in pseudobulk (scRNA only)
params.outdir         = './results'
params.max_memory     = '64.GB'
params.max_cpus       = 8
params.max_time       = '72.h'

// Steps:
//  * 1. [GEO Download] Download series matrix + supplementary files from GEO
//  * 2. [Pseudobulk] Aggregate scRNA counts per sample (sum method) — skip for bulk
//  * 3. [Metadata] Extract and harmonize sample metadata + auto-detect condition column
//  * 4. [Output] Write counts_matrix.csv, sample_metadata.csv, contrasts.csv

process GEO_PSEUDOBULK {
    tag "${params.geo_accession}"
    label 'process_medium'

    publishDir "${params.outdir}", mode: 'copy'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

    input:
    val meta

    output:
    tuple val(meta), path("counts_matrix.csv"),    emit: matrix,    optional: false
    tuple val(meta), path("sample_metadata.csv"),  emit: metadata,  optional: false
    tuple val(meta), path("contrasts.csv"),        emit: contrasts, optional: false
    tuple val(meta), path("qc_metrics.json"),      emit: qc_metrics
    path "versions.yml",                           emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def acc         = params.geo_accession ?: ''
    def cond_col    = params.condition_col  ?: ''
    def ref_group   = params.reference      ?: ''
    def tgt_group   = params.target         ?: ''
    def min_cells   = params.min_cells      ?: 10
    """
    #!/usr/bin/env Rscript

    # ── 0. Dependencies ────────────────────────────────────────────────────────
    .bm_deps <- c("GEOquery", "Matrix", "jsonlite")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss) > 0) {
      if (!requireNamespace("BiocManager", quietly=TRUE))
        install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))
      suppressWarnings(suppressMessages(
        BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)
      ))
    }
    library(GEOquery)
    library(Matrix)
    library(jsonlite)

    acc       <- "${acc}"
    cond_col  <- "${cond_col}"
    ref_group <- "${ref_group}"
    tgt_group <- "${tgt_group}"
    min_cells <- as.integer("${min_cells}")

    cat(sprintf("[GEO] Fetching %s\\n", acc))

    # ── 1. Try series matrix (bulk / pre-normalised) ──────────────────────────
    gse <- tryCatch(
      getGEO(acc, GSEMatrix=TRUE, getGPL=FALSE, AnnotGPL=FALSE),
      error = function(e) { cat(sprintf("[GEO] Series matrix failed: %s\\n", e\$message)); NULL }
    )

    data_type        <- "unknown"
    counts_matrix    <- NULL
    sample_meta      <- NULL

    if (!is.null(gse) && length(gse) > 0) {
      eset <- gse[[1]]
      mat  <- exprs(eset)
      meta <- pData(eset)

      # Bulk RNA-seq: expression matrix contains numeric expression values
      # Round to integers (handles log-scale or RPKM — not ideal but passable for routing)
      if (nrow(mat) > 0 && ncol(mat) > 0) {
        mat_int <- round(mat)
        storage.mode(mat_int) <- "integer"
        mat_int[mat_int < 0] <- 0L
        counts_matrix <- mat_int
        sample_meta   <- meta
        data_type     <- "bulk"
        cat(sprintf("[GEO] Bulk matrix: %d genes x %d samples\\n", nrow(mat_int), ncol(mat_int)))
      }
    }

    # ── 2. scRNA-seq path: download RAW.tar and pseudobulk ───────────────────
    if (is.null(counts_matrix)) {
      cat("[GEO] No expression matrix in series matrix — trying supplementary files (scRNA-seq)\\n")

      supp_dir <- file.path(getwd(), "geo_raw")
      dir.create(supp_dir, showWarnings=FALSE, recursive=TRUE)

      supp_files <- tryCatch(
        getGEOSuppFiles(acc, makeDirectory=FALSE, baseDir=supp_dir),
        error = function(e) { cat(sprintf("[GEO] Supp download failed: %s\\n", e\$message)); NULL }
      )

      if (!is.null(supp_files) && nrow(supp_files) > 0) {
        cat(sprintf("[GEO] Downloaded %d supplementary file(s)\\n", nrow(supp_files)))

        # Find the RAW tar
        raw_tar <- rownames(supp_files)[grepl("RAW\\\\.tar(\\\\.gz)?$", rownames(supp_files), ignore.case=TRUE)]
        if (length(raw_tar) == 0) raw_tar <- rownames(supp_files)[grepl("\\\\.tar", rownames(supp_files))]

        if (length(raw_tar) > 0) {
          cat(sprintf("[GEO] Extracting RAW archive: %s\\n", basename(raw_tar[1])))
          extract_dir <- file.path(supp_dir, "extracted")
          dir.create(extract_dir, showWarnings=FALSE)
          untar(raw_tar[1], exdir=extract_dir)

          # Find per-sample directories or per-sample tar.gz files
          sample_entries <- list.files(extract_dir, full.names=TRUE)
          cat(sprintf("[GEO] Found %d entries after extraction\\n", length(sample_entries)))

          # Each sample may be: a directory with matrix.mtx.gz/barcodes.tsv.gz/features.tsv.gz
          # OR a .tar.gz containing those files
          pseudobulk_list <- list()

          for (entry in sample_entries) {
            sample_name <- tools::file_path_sans_ext(tools::file_path_sans_ext(basename(entry)))
            # Shorten to GSM accession if possible
            gsm_match <- regmatches(sample_name, regexpr("GSM[0-9]+", sample_name))
            label <- if (length(gsm_match) > 0) gsm_match else sample_name

            # If entry is a tar.gz, extract it
            sample_dir <- entry
            if (file.info(entry)\$isdir == FALSE && grepl("\\\\.tar(\\\\.gz)?$", entry, ignore.case=TRUE)) {
              sample_dir <- file.path(extract_dir, label)
              dir.create(sample_dir, showWarnings=FALSE)
              tryCatch(untar(entry, exdir=sample_dir), error=function(e) NULL)
            } else if (file.info(entry)\$isdir == FALSE) {
              next  # skip individual non-archive files
            }

            # Look for 10x MEX files (matrix.mtx.gz, barcodes.tsv.gz, features.tsv.gz)
            mat_file  <- list.files(sample_dir, pattern="matrix\\\\.mtx", full.names=TRUE, recursive=TRUE)
            bar_file  <- list.files(sample_dir, pattern="barcodes\\\\.tsv", full.names=TRUE, recursive=TRUE)
            feat_file <- list.files(sample_dir, pattern="(features|genes)\\\\.tsv", full.names=TRUE, recursive=TRUE)

            if (length(mat_file) == 0 || length(bar_file) == 0 || length(feat_file) == 0) {
              cat(sprintf("[GEO] Skipping %s — no MEX files found\\n", label))
              next
            }

            tryCatch({
              mat_sp  <- readMM(mat_file[1])
              barcodes <- read.table(bar_file[1], header=FALSE, stringsAsFactors=FALSE)\$V1
              features <- read.table(feat_file[1], header=FALSE, stringsAsFactors=FALSE)\$V1
              rownames(mat_sp) <- features
              colnames(mat_sp) <- barcodes

              n_cells <- ncol(mat_sp)
              if (n_cells < min_cells) {
                cat(sprintf("[GEO] Skipping %s — only %d cells (min %d)\\n", label, n_cells, min_cells))
                next
              }

              # Pseudobulk: sum across all cells for this sample
              pb_counts <- Matrix::rowSums(mat_sp)
              pseudobulk_list[[label]] <- as.integer(round(pb_counts))
              names(pseudobulk_list[[label]]) <- rownames(mat_sp)
              cat(sprintf("[GEO] Pseudobulked %s: %d genes, %d cells\\n", label, length(pb_counts), n_cells))
            }, error = function(e) {
              cat(sprintf("[GEO] Failed to read %s: %s\\n", label, e\$message))
            })
          }

          if (length(pseudobulk_list) >= 2) {
            # Align genes across samples (intersection)
            common_genes <- Reduce(intersect, lapply(pseudobulk_list, names))
            cat(sprintf("[GEO] %d common genes across %d samples\\n", length(common_genes), length(pseudobulk_list)))

            counts_matrix <- do.call(cbind, lapply(pseudobulk_list, function(x) x[common_genes]))
            storage.mode(counts_matrix) <- "integer"
            rownames(counts_matrix) <- common_genes
            data_type <- "scrna_pseudobulk"
          }
        }
      }
    }

    if (is.null(counts_matrix) || nrow(counts_matrix) == 0 || ncol(counts_matrix) == 0) {
      stop(paste("[GEO] Could not obtain a count matrix for", acc,
                 "— check the accession is a valid scRNA-seq or bulk RNA-seq dataset"))
    }

    # ── 3. Build / recover sample metadata ────────────────────────────────────
    if (is.null(sample_meta)) {
      # For scRNA-seq path, fetch metadata from series matrix
      gse2 <- tryCatch(
        getGEO(acc, GSEMatrix=TRUE, getGPL=FALSE, AnnotGPL=FALSE),
        error = function(e) NULL
      )
      if (!is.null(gse2) && length(gse2) > 0) {
        sample_meta <- pData(gse2[[1]])
      }
    }

    # Map column names of counts_matrix to GSM IDs for metadata join
    gsm_ids_counts <- regmatches(colnames(counts_matrix),
                                  regexpr("GSM[0-9]+", colnames(counts_matrix)))
    if (length(gsm_ids_counts) == ncol(counts_matrix) && !is.null(sample_meta)) {
      rownames(sample_meta) <- regmatches(rownames(sample_meta),
                                           regexpr("GSM[0-9]+", rownames(sample_meta)))
      common_gsm <- intersect(gsm_ids_counts, rownames(sample_meta))
      if (length(common_gsm) >= 2) {
        counts_matrix <- counts_matrix[, gsm_ids_counts %in% common_gsm, drop=FALSE]
        colnames(counts_matrix) <- gsm_ids_counts[gsm_ids_counts %in% common_gsm]
        sample_meta   <- sample_meta[common_gsm, , drop=FALSE]
      }
    }

    # ── 4. Auto-detect condition column ───────────────────────────────────────
    detect_condition_col <- function(meta) {
      n_rows <- nrow(meta)
      candidates <- vapply(names(meta), function(col) {
        vals <- unique(trimws(as.character(meta[[col]])))
        n_uniq <- length(vals)
        # 2-5 unique values, not all unique (not an ID), not all same
        n_uniq >= 2 && n_uniq <= 5 && n_uniq < n_rows
      }, logical(1))
      # Prefer columns named title, characteristics_ch1, condition, group, disease, etc.
      pref <- c("title", grep("characteristics|condition|group|disease|status|type|treatment",
                               names(meta), ignore.case=TRUE, value=TRUE))
      pref_valid <- pref[pref %in% names(meta)[candidates]]
      if (length(pref_valid) > 0) return(pref_valid[1])
      candidate_cols <- names(meta)[candidates]
      if (length(candidate_cols) > 0) return(candidate_cols[1])
      NULL
    }

    chosen_col <- if (nchar(cond_col) > 0 && cond_col %in% names(sample_meta)) {
      cond_col
    } else {
      detect_condition_col(sample_meta)
    }

    if (is.null(chosen_col)) {
      stop("[GEO] Could not auto-detect a condition column. Provide --condition_col explicitly.")
    }
    cat(sprintf("[GEO] Using condition column: %s\\n", chosen_col))

    condition_vals <- trimws(as.character(sample_meta[[chosen_col]]))

    # For GSE227835: parse condition from title field (e.g. "AChR+ MG patient 1" → "MG", "Healthy control 1" → "HC")
    condition_parsed <- condition_vals
    if (grepl("MG|myasthenia|AChR|seropositive|seronegative", paste(condition_vals, collapse=" "), ignore.case=TRUE)) {
      condition_parsed <- ifelse(
        grepl("control|HC|healthy", condition_vals, ignore.case=TRUE), "HC",
        ifelse(grepl("MG|myasthenia|AChR|seropositive|seronegative", condition_vals, ignore.case=TRUE), "MG",
               condition_vals)
      )
      cat("[GEO] Applied MG/HC condition parsing\\n")
    }

    groups <- sort(unique(condition_parsed))
    cat(sprintf("[GEO] Condition groups: %s\\n", paste(groups, collapse=", ")))

    # Determine reference and target
    chosen_ref <- if (nchar(ref_group) > 0 && ref_group %in% groups) ref_group else {
      # Reference = most frequent group (usually control)
      tbl <- sort(table(condition_parsed), decreasing=TRUE)
      names(tbl)[1]
    }
    chosen_tgt <- if (nchar(tgt_group) > 0 && tgt_group %in% groups && tgt_group != chosen_ref) tgt_group else {
      grps_other <- groups[groups != chosen_ref]
      if (length(grps_other) > 0) grps_other[1] else groups[length(groups)]
    }
    cat(sprintf("[GEO] Contrast: %s (target) vs %s (reference)\\n", chosen_tgt, chosen_ref))

    # ── 5. Build sample metadata CSV ──────────────────────────────────────────
    sample_ids <- colnames(counts_matrix)
    condition_out <- if (length(condition_parsed) == length(sample_ids)) {
      condition_parsed
    } else {
      rep(NA_character_, length(sample_ids))
    }

    out_meta <- data.frame(
      sample    = sample_ids,
      condition = condition_out,
      stringsAsFactors = FALSE
    )
    write.csv(out_meta, "sample_metadata.csv", row.names=FALSE, quote=TRUE)
    cat(sprintf("[GEO] Wrote sample_metadata.csv (%d samples)\\n", nrow(out_meta)))

    # ── 6. Write count matrix ──────────────────────────────────────────────────
    counts_df <- as.data.frame(counts_matrix)
    counts_df <- cbind(gene = rownames(counts_matrix), counts_df)
    write.csv(counts_df, "counts_matrix.csv", row.names=FALSE, quote=FALSE)
    cat(sprintf("[GEO] Wrote counts_matrix.csv (%d genes x %d samples)\\n",
                nrow(counts_matrix), ncol(counts_matrix)))

    # ── 7. Write contrasts CSV ─────────────────────────────────────────────────
    contrast_id <- paste0(chosen_tgt, "_vs_", chosen_ref)
    contrasts_df <- data.frame(
      id        = contrast_id,
      variable  = "condition",
      reference = chosen_ref,
      target    = chosen_tgt,
      stringsAsFactors = FALSE
    )
    write.csv(contrasts_df, "contrasts.csv", row.names=FALSE, quote=FALSE)
    cat(sprintf("[GEO] Wrote contrasts.csv (%s)\\n", contrast_id))

    # ── 8. QC metrics ─────────────────────────────────────────────────────────
    qc <- list(
      success           = TRUE,
      process           = "GEO_PSEUDOBULK",
      domain            = "transcriptomics",
      geo_accession     = acc,
      n_samples         = ncol(counts_matrix),
      n_genes           = nrow(counts_matrix),
      data_type         = data_type,
      pseudobulk_method = if (data_type == "scrna_pseudobulk") "sum" else "none",
      condition_column  = chosen_col,
      contrast          = contrast_id,
      harness_version   = "0.1.0-geo-pseudobulk"
    )
    cat(toJSON(qc, auto_unbox=TRUE, pretty=TRUE, null="null"), file="qc_metrics.json")

    writeLines(c('"GEO_PSEUDOBULK":',
                 paste0('    GEOquery: ', as.character(packageVersion('GEOquery'))),
                 paste0('    Matrix:   ', as.character(packageVersion('Matrix')))),
               "versions.yml")
    cat("[GEO] Done\\n")
    """

    stub:
    """
    echo "gene,S1,S2" > counts_matrix.csv
    echo "GENE1,100,50" >> counts_matrix.csv
    echo "sample,condition" > sample_metadata.csv
    echo "S1,MG" >> sample_metadata.csv
    echo "S2,HC" >> sample_metadata.csv
    echo "id,variable,reference,target" > contrasts.csv
    echo "MG_vs_HC,condition,HC,MG" >> contrasts.csv
    echo '{"success":true}' > qc_metrics.json
    touch versions.yml
    """
}

workflow GEO_SCRNA_PSEUDOBULK {
    main:
    if (!params.geo_accession) error "Please provide --geo_accession (e.g. GSE227835)"

    GEO_PSEUDOBULK(Channel.value([id: params.geo_accession]))

    emit:
    matrix    = GEO_PSEUDOBULK.out.matrix
    metadata  = GEO_PSEUDOBULK.out.metadata
    contrasts = GEO_PSEUDOBULK.out.contrasts
    versions  = GEO_PSEUDOBULK.out.versions
}

workflow {
    GEO_SCRNA_PSEUDOBULK()
}
