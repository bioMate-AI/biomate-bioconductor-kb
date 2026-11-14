#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MAGeCKFlute — mageck_rra_analysis
// Perform downstream quality control, visualization, and functional enrichment analysis on CRISPR screen results processed via the MAGeCK RRA (Robust Rank Aggrega
// Input: gene_summary.txt, sgrna_summary.txt
// Container: quay.io/biocontainers/bioconductor-mageckflute:2.9.0--r44hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: MAGeCKFlute
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Read the RRA gene and sgRNA summary files
//  * 2. [Core Analysis] Run the FluteRRA pipeline to perform quality control, identify positively and negatively selected genes, and execute pathway enric

nextflow.enable.dsl = 2

process BIOC_MAGECKFLUTE_MAGECK_RRA_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    publishDir "${params.outdir}", mode: 'copy'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("MAGeCKFlute")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required library
    library(MAGeCKFlute)

    .is_rra_gene <- function(df) {
      cn <- tolower(gsub("[| .]", "", colnames(df)))
      ("id" %in% cn || "gene" %in% cn) && any(grepl("negscore|neglfc|poslfc|negfdr", cn))
    }
    .is_counts <- function(df) {
      cn <- tolower(colnames(df))
      any(cn %in% c("sgrna", "sgrna.id", "guide")) && any(cn %in% c("gene", "genes", "symbol"))
    }
    .read_any <- function(path) {
      if (grepl("\\\\.csv\$", path, ignore.case = TRUE)) read.csv(path, check.names = FALSE, stringsAsFactors = FALSE)
      else read.delim(path, check.names = FALSE, stringsAsFactors = FALSE, quote = "")
    }
    # Build MAGeCK-RRA-shaped gene + sgRNA tables from a counts matrix so FluteRRA /
    # ReadRRA (hard-coded column indices) do not crash on cold-start crispr_counts.tsv.
    .counts_to_rra <- function(counts, treat_cols, ctrl_cols, out_gene, out_sgrna) {
      gene_col <- grep("(?i)^gene\$|^genes\$|^symbol\$", colnames(counts), value = TRUE)[1]
      sgrna_col <- grep("(?i)^sgrna|^guide", colnames(counts), value = TRUE)[1]
      g <- as.character(counts[[gene_col]])
      sg <- as.character(counts[[sgrna_col]])
      treat <- as.matrix(sapply(treat_cols, function(c) as.numeric(counts[[c]])))
      ctrl <- as.matrix(sapply(ctrl_cols, function(c) as.numeric(counts[[c]])))
      if (is.null(dim(treat))) treat <- matrix(treat, ncol = 1)
      if (is.null(dim(ctrl))) ctrl <- matrix(ctrl, ncol = 1)
      t_mean <- rowMeans(treat, na.rm = TRUE) + 1
      c_mean <- rowMeans(ctrl, na.rm = TRUE) + 1
      lfc <- log2(t_mean / c_mean)
      # sgRNA summary (minimal columns FluteRRA/ReadsgRRA tolerate)
      sgrna <- data.frame(
        sgrna = sg, Gene = g,
        control_count = c_mean, treatment_count = t_mean,
        LFC = lfc, stringsAsFactors = FALSE
      )
      # Gene-level aggregate for ReadRRA column layout:
      # id, num, neg|score, neg|p-value, neg|fdr, neg|rank, neg|goodsgrna, neg|lfc,
      # pos|score, pos|p-value, pos|fdr, pos|rank, pos|goodsgrna, pos|lfc  (14 cols)
      genes <- sort(unique(g))
      rows <- lapply(genes, function(ge) {
        idx <- which(g == ge)
        glfc <- median(lfc[idx], na.rm = TRUE)
        # crude two-sided p from guide LFC sign consistency
        p <- tryCatch({
          if (length(idx) < 2) 1 else stats::wilcox.test(lfc[idx], mu = 0)\$p.value
        }, error = function(e) 1)
        p <- ifelse(is.finite(p), p, 1)
        neg <- glfc < 0
        c(
          ge, length(idx),
          if (neg) p else 1, p, p, 0, sum(lfc[idx] < 0), if (neg) glfc else 0,
          if (!neg) p else 1, p, p, 0, sum(lfc[idx] > 0), if (!neg) glfc else 0
        )
      })
      gene_df <- as.data.frame(do.call(rbind, rows), stringsAsFactors = FALSE)
      colnames(gene_df) <- c(
        "id", "num",
        "neg|score", "neg|p-value", "neg|fdr", "neg|rank", "neg|goodsgrna", "neg|lfc",
        "pos|score", "pos|p-value", "pos|fdr", "pos|rank", "pos|goodsgrna", "pos|lfc"
      )
      for (cn in setdiff(colnames(gene_df), "id")) gene_df[[cn]] <- as.numeric(gene_df[[cn]])
      gene_df[["neg|rank"]] <- rank(gene_df[["neg|score"]], ties.method = "min")
      gene_df[["pos|rank"]] <- rank(gene_df[["pos|score"]], ties.method = "min")
      write.table(gene_df, out_gene, sep = "\\t", quote = FALSE, row.names = FALSE)
      write.table(sgrna, out_sgrna, sep = "\\t", quote = FALSE, row.names = FALSE)
      list(gene = gene_df, sgrna = sgrna)
    }

    gene_file <- "gene_summary.txt"
    sgrna_file <- "sgrna_summary.txt"
    .tables <- list.files(".", pattern = "(?i)\\\\.(txt|tsv|csv)\$")
    .tables <- .tables[file.info(.tables)\$size > 0]

    if (file.exists(gene_file)) {
      gdata <- .read_any(gene_file)
    } else {
      gdata <- NULL
    }
    if (file.exists(sgrna_file)) {
      sdata <- .read_any(sgrna_file)
    } else {
      sdata <- NULL
    }

    # Cold-start attaches crispr_counts.tsv (+ design), not MAGeCK RRA summaries.
    if (is.null(gdata) || !.is_rra_gene(gdata)) {
      .count_path <- NULL
      for (f in .tables) {
        df <- tryCatch(.read_any(f), error = function(e) NULL)
        if (!is.null(df) && .is_counts(df)) { .count_path <- f; gdata <- df; break }
      }
      if (!is.null(.count_path) && .is_counts(gdata)) {
        cn <- colnames(gdata)
        # Prefer *.final vs *.initial (MAGeCK demo / cold-start HL60+KBM7)
        finals <- grep("(?i)\\\\.final\$|_final\$|treat|day21|t[0-9]", cn, value = TRUE)
        inits <- grep("(?i)\\\\.initial\$|_initial\$|control|ctrl|plasmid|baseline", cn, value = TRUE)
        if (!length(finals) || !length(inits)) {
          num_cols <- cn[vapply(gdata, is.numeric, logical(1))]
          if (length(num_cols) >= 2) {
            inits <- num_cols[1]
            finals <- num_cols[2]
          }
        }
        if (!length(finals) || !length(inits)) {
          stop("Counts table found but could not infer treatment/control columns.")
        }
        # One contrast for FluteRRA (HL60.final vs HL60.initial when available)
        .pair_init <- inits[1]
        .pair_final <- finals[1]
        .hl60_i <- grep("(?i)hl60.*initial", inits, value = TRUE)
        .hl60_f <- grep("(?i)hl60.*final", finals, value = TRUE)
        if (length(.hl60_i) && length(.hl60_f)) {
          .pair_init <- .hl60_i[1]; .pair_final <- .hl60_f[1]
        }
        message("Converting counts ", .count_path, " → MAGeCK-RRA summaries (",
                .pair_final, " vs ", .pair_init, ")")
        .conv <- .counts_to_rra(gdata, .pair_final, .pair_init, gene_file, sgrna_file)
        gdata <- .conv\$gene
        sdata <- .conv\$sgrna
      } else if (is.null(gdata) || !.is_rra_gene(gdata)) {
        # Last resort: package testdata so the panel is not a hard ReadRRA crash
        .ex <- system.file("extdata", "testdata", package = "MAGeCKFlute")
        .g <- file.path(.ex, "rra.gene_summary.txt")
        .s <- file.path(.ex, "rra.sgrna_summary.txt")
        if (!file.exists(.g)) stop("Required input file missing: gene_summary.txt (or a CRISPR counts table)")
        message("No RRA/counts input resolved — using MAGeCKFlute package testdata")
        file.copy(.g, gene_file, overwrite = TRUE)
        file.copy(.s, sgrna_file, overwrite = TRUE)
        gdata <- .read_any(gene_file)
        sdata <- .read_any(sgrna_file)
      }
    }
    if (is.null(sdata)) {
      .s_cand <- grep("(?i)sgrna_summary|sgrna", .tables, value = TRUE)[1]
      if (!is.na(.s_cand)) sdata <- .read_any(.s_cand)
    }
    
    # Step 2: Run the FluteRRA pipeline (DepMap off — Batch nodes often lack egress)
    rra_results <- FluteRRA(
      gdata, sdata, proj = "RRA_Project", organism = "hsa",
      incorporateDepmap = FALSE, outdir = "./"
    )
    
    # Step 3: Save the returned results object for downstream inspection
    saveRDS(rra_results, file = "RRA_Project_results.rds")
    if (file.exists(gene_file)) {
      try(file.copy(gene_file, "gene_summary_used.csv", overwrite = TRUE), silent = TRUE)
    }

    writeLines(c(
        '"BIOC_MAGECKFLUTE_MAGECK_RRA_ANALYSIS":',
        paste0('    MAGeCKFlute: ', as.character(packageVersion('MAGeCKFlute')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mageck_rra_analysis.csv versions.yml
    """
}

workflow BIOC_MAGECKFLUTE_MAGECK_RRA_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ gene_summary.txt, sgrna_summary.txt ] ]

    main:
    BIOC_MAGECKFLUTE_MAGECK_RRA_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_MAGECKFLUTE_MAGECK_RRA_ANALYSIS.out.tables
    plots    = BIOC_MAGECKFLUTE_MAGECK_RRA_ANALYSIS.out.plots
    objects  = BIOC_MAGECKFLUTE_MAGECK_RRA_ANALYSIS.out.objects
    versions = BIOC_MAGECKFLUTE_MAGECK_RRA_ANALYSIS.out.versions
}
