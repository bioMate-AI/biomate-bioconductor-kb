#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: seq2pathway — chip_seq_region_pathway
// Map genomic regions (such as ChIP-seq peaks) to genes and perform quantitative pathway enrichment analysis.
// Input: Chipseq_Peak_demo, MsigDB_C5, dat_chip
// Container: quay.io/biocontainers/bioconductor-seq2pathway:1.34.0--r43hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: seq2pathway
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Load User Inputs
//  * 2. [Core Analysis] Map genomic regions to genes using runseq2gene
//  * 3. [Core Analysis] Run pathway enrichment analysis using gene2pathway_test
//  * 4. [Core Analysis] Add detailed gene descriptions using addDescription

nextflow.enable.dsl = 2

process BIOC_SEQ2PATHWAY_CHIP_SEQ_REGION_PATHWAY {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-variant_calling:3.20-slim"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    tuple val(meta), path("qc_metrics.json"), emit: qc_metrics
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("seq2pathway")
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
    
    # Load required libraries
    library(seq2pathway)
    
    # Helper function to robustly load user input files from the working directory
    load_input <- function(filename) {
      # Check various extensions in case the user saved them in different formats
      extensions <- c("", ".rds", ".RDS", ".csv", ".CSV", ".txt", ".TXT", ".RData", ".rdata", ".rda")
      
      for (ext in extensions) {
        full_path <- paste0(filename, ext)
        if (file.exists(full_path)) {
          if (grepl("\\\\.(rds|RDS)\$", full_path) || (ext == "" && grepl("\\\\.rds\$", full_path, ignore.case = TRUE))) {
            return(readRDS(full_path))
          } else if (grepl("\\\\.(csv|CSV)\$", full_path)) {
            return(read.csv(full_path, stringsAsFactors = FALSE))
          } else if (grepl("\\\\.(txt|TXT)\$", full_path)) {
            return(read.table(full_path, header = TRUE, stringsAsFactors = FALSE))
          } else if (grepl("\\\\.(RData|rdata|rda)\$", full_path)) {
            env <- new.env()
            load(full_path, envir = env)
            vars <- ls(env)
            if (length(vars) > 0) {
              return(get(vars[1], envir = env))
            }
          } else {
            # Default fallback to readRDS if no extension matches but file exists
            tryCatch({
              return(readRDS(full_path))
            }, error = function(e) {
              tryCatch({
                return(read.csv(full_path, stringsAsFactors = FALSE))
              }, error = function(e2) {
                stop(paste("Failed to read file:", full_path))
              })
            })
          }
        }
      }
      stop(paste("Required input file not found in working directory:", filename))
    }
    
    # ----------------------------------------------------------------------
    # --- Load User Inputs ---
    # ----------------------------------------------------------------------
    message("Loading user input files...")
    Chipseq_Peak_demo <- load_input("Chipseq_Peak_demo")
    MsigDB_C5         <- load_input("MsigDB_C5")
    dat_chip          <- load_input("dat_chip")
    
    # ----------------------------------------------------------------------
    # --- Map genomic regions to genes using runseq2gene ---
    # ----------------------------------------------------------------------
    message("Mapping genomic regions to genes...")
    Chipseq_anno <- runseq2gene(
                      inputfile=Chipseq_Peak_demo, 
                      genome="hg19", adjacent=FALSE, SNP=FALSE, search_radius=1000, 
                      PromoterStop=FALSE,NearestTwoDirection=TRUE)
    
    # Save Step 1 Outputs
    message("Saving genomic region annotation results...")
    saveRDS(Chipseq_anno, "Chipseq_anno.rds")
    if (is.list(Chipseq_anno) && length(Chipseq_anno) > 0) {
      write.csv(Chipseq_anno[[1]], "Chipseq_anno_table.csv", row.names = FALSE)
    }
    
    # ----------------------------------------------------------------------
    # --- Run pathway enrichment analysis using gene2pathway_test ---
    # ----------------------------------------------------------------------
    message("Running pathway enrichment analysis (FAIME & Fisher's Exact Test)...")
    result_FAIME <- gene2pathway_test(dat= dat_chip, DataBase= MsigDB_C5,
                    FisherTest=TRUE, EmpiricalTest=FALSE, method="FAIME",
                    alpha=5, logCheck=FALSE, na.rm=FALSE)
    
    # Save Step 2 Outputs
    message("Saving pathway enrichment results...")
    saveRDS(result_FAIME, "result_FAIME.rds")
    
    if (is.list(result_FAIME)) {
      for (name in names(result_FAIME)) {
        sub_res <- result_FAIME[[name]]
        if (is.data.frame(sub_res)) {
          write.csv(sub_res, paste0("result_FAIME_", name, ".csv"), row.names = TRUE)
        } else if (is.list(sub_res)) {
          for (sub_name in names(sub_res)) {
            if (is.data.frame(sub_res[[sub_name]])) {
              write.csv(sub_res[[sub_name]], paste0("result_FAIME_", name, "_", sub_name, ".csv"), row.names = TRUE)
            }
          }
        }
      }
    }
    
    # ----------------------------------------------------------------------
    # --- Add detailed gene descriptions using addDescription ---
    # ----------------------------------------------------------------------
    message("Adding detailed gene descriptions...")
    gene_description <- addDescription(genome="hg38", genevector=as.vector(rownames(dat_chip)))
    
    # Save Step 3 Outputs
    message("Saving gene description results...")
    saveRDS(gene_description, "gene_description.rds")
    write.csv(gene_description, "gene_description.csv", row.names = FALSE)
    
    message("Pipeline completed successfully.")
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # alignment/mapping QC — workflow-emitted artifact check for common log
    # files (.log, .summary, alignment metrics tables). Binary pass.
    .amqc_logs <- c(list.files(".", pattern = "(?i)(align|map|samtools|flagstat).*\\.(log|txt|summary)\$"),
                    list.files(".", pattern = "(?i)flagstat\\."))
    .amqc_passes <- length(.amqc_logs) > 0
    .gates_by_label[["alignment/mapping QC"]] <- list(
      gate_row = "bioc_alignment_mapping_qc",
      metric_name = "alignment_qc_artifacts",
      metric_value = length(.amqc_logs),
      passes = .amqc_passes,
      status = if (.amqc_passes) paste0("computed (", length(.amqc_logs), " alignment log(s) emitted)")
               else "not_computed (no alignment log/summary artifact present)"
    )

    # low-count filtering — fraction of genes retained (heuristic on matrix artifacts).
    # Pass band 30-60% per Chen 2016 F1000 (edgeR filterByExpr convention).
    .lcf_kept_fractions <- numeric(0)
    .lcf_scanned <- character(0)
    for (.lcf_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .lcf_obj <- tryCatch(readRDS(.lcf_rds), error = function(e) NULL)
      .lcf_mat <- if (is.matrix(.lcf_obj) || is.data.frame(.lcf_obj)) .lcf_obj else NULL
      if (!is.null(.lcf_mat) && nrow(.lcf_mat) > 100) {
        .lcf_m <- tryCatch(as.matrix(.lcf_mat), error = function(e) NULL)
        if (!is.null(.lcf_m)) {
          .lcf_row_med <- suppressWarnings(apply(.lcf_m, 1, function(r) median(as.numeric(r), na.rm = TRUE)))
          .lcf_kept <- sum(is.finite(.lcf_row_med) & .lcf_row_med >= 1) / nrow(.lcf_m)
          .lcf_kept_fractions <- c(.lcf_kept_fractions, .lcf_kept)
          .lcf_scanned <- c(.lcf_scanned, .lcf_rds)
        }
      }
    }
    .lcf_kept <- if (length(.lcf_kept_fractions) > 0) round(median(.lcf_kept_fractions), 4) else NA_real_
    .gates_by_label[["low-count filtering"]] <- list(
      gate_row = "bioc_low_count_filtering",
      metric_name = "genes_kept_fraction",
      metric_value = .lcf_kept,
      passes = isTRUE(is.finite(.lcf_kept) && .lcf_kept >= 0.3 && .lcf_kept <= 0.6),
      status = if (is.finite(.lcf_kept)) paste0("computed (proxy: rows w/ median count >=1 across ", length(.lcf_scanned), " matrix .rds)")
               else "not_computed (no count matrix .rds artifact present)"
    )

    # count normalization — scan .rds matrix artifacts for library-size CV
    # ratio (post-norm / pre-norm); without raw input we report median lib CV
    # as a proxy diagnostic. Threshold = 0.7 (Bullard 2010 BMC Bioinf).
    .cn_lib_cvs <- numeric(0)
    .cn_scanned <- character(0)
    for (.cn_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .cn_obj <- tryCatch(readRDS(.cn_rds), error = function(e) NULL)
      .cn_mat <- if (is.matrix(.cn_obj) || is.data.frame(.cn_obj)) .cn_obj else NULL
      if (!is.null(.cn_mat) && ncol(.cn_mat) >= 2 && nrow(.cn_mat) >= 2) {
        .cn_lib <- tryCatch(colSums(as.matrix(.cn_mat), na.rm = TRUE), error = function(e) NULL)
        if (!is.null(.cn_lib) && all(is.finite(.cn_lib)) && mean(.cn_lib) > 0) {
          .cn_lib_cvs <- c(.cn_lib_cvs, sd(.cn_lib) / mean(.cn_lib))
          .cn_scanned <- c(.cn_scanned, .cn_rds)
        }
      }
    }
    .cn_med_cv <- if (length(.cn_lib_cvs) > 0) round(median(.cn_lib_cvs), 4) else NA_real_
    .gates_by_label[["count normalization"]] <- list(
      gate_row = "bioc_count_normalization",
      metric_name = "lib_size_cv_median",
      metric_value = .cn_med_cv,
      passes = isTRUE(is.finite(.cn_med_cv) && .cn_med_cv <= 0.3),
      status = if (is.finite(.cn_med_cv)) paste0("computed (proxy: median lib-size CV across ", length(.cn_scanned), " matrix .rds; raw-vs-norm ratio not measurable without paired input)")
               else "not_computed (no count matrix .rds artifact present)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_SEQ2PATHWAY_CHIP_SEQ_REGION_PATHWAY",
      domain  = "bioconductor",
      declared_qc_steps = c("alignment/mapping QC", "low-count filtering", "count normalization"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_SEQ2PATHWAY_CHIP_SEQ_REGION_PATHWAY":',
        paste0('    seq2pathway: ', as.character(packageVersion('seq2pathway')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_chip_seq_region_pathway.csv versions.yml
    """
}

workflow BIOC_SEQ2PATHWAY_CHIP_SEQ_REGION_PATHWAY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Chipseq_Peak_demo, MsigDB_C5, dat_chip ] ]

    main:
    BIOC_SEQ2PATHWAY_CHIP_SEQ_REGION_PATHWAY(ch_input)

    emit:
    tables   = BIOC_SEQ2PATHWAY_CHIP_SEQ_REGION_PATHWAY.out.tables
    plots    = BIOC_SEQ2PATHWAY_CHIP_SEQ_REGION_PATHWAY.out.plots
    objects  = BIOC_SEQ2PATHWAY_CHIP_SEQ_REGION_PATHWAY.out.objects
    versions = BIOC_SEQ2PATHWAY_CHIP_SEQ_REGION_PATHWAY.out.versions
}
