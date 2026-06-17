#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: genomicalignments — read_counting_for_differential_expression
// Count aligned reads overlapping genomic features to prepare a count matrix for downstream differential expression analysis.
// Input: bamfiles, features
// Container: quay.io/biocontainers/bioconductor-genomicalignments:1.46.0--r45h01b2380_0
// R packages: DESeq2, biocmanager, edgeR, GenomicAlignments, GenomicFeatures, pasillabamsubset, Rsamtools
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// QC: alignment/mapping QC

nextflow.enable.dsl = 2

process BIOC_GENOMICALIGNMENTS_READ_COUNTING_FOR_DIFFERENTIAL_EXPRESSION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-genomicalignments:1.46.0--r45h01b2380_0"

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
    .bm_deps <- c("DESeq2", "biocmanager", "edgeR", "GenomicAlignments", "GenomicFeatures", "pasillabamsubset", "Rsamtools", "SummarizedExperiment")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }

    # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
    for (.bm_d in list.files(".", full.names = TRUE)) {
      if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
        for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
          if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
        }
      }
    }
    
    # --- Load GenomicAlignments and downstream analysis packages ---
    library(GenomicAlignments)
    library(SummarizedExperiment)
    library(DESeq2)
    library(edgeR)
    
    # --- Define genomic features of interest and BAM files from ---
    if (file.exists("features.rds")) {
        features <- readRDS("features.rds")
    } else if (file.exists("features")) {
        features <- readRDS("features")
    } else {
        stop("Error: Genomic features file ('features.rds' or 'features') not found in the working directory.")
    }
    
    fls <- list.files(pattern = "\\\\.bam\$", full.names = TRUE)
    if (length(fls) == 0) {
        stop("Error: No BAM files (*.bam) found in the working directory.")
    }
    
    # Assign names to the file list to ensure the overlap object has valid sample names
    names(fls) <- tools::file_path_sans_ext(basename(fls))
    
    # --- Count overlaps between reads and features using ---
    olap <- summarizeOverlaps(features, fls)
    
    # --- Convert the overlap object into a DESeqDataSet or DGEList ---
    deseq <- DESeqDataSet(olap, design= ~ 1)
    edger <- DGEList(assay(olap), group=rownames(colData(olap)))
    
    # --- Save outputs to the working directory ---
    write.csv(assay(olap), file = "read_counts.csv", row.names = TRUE)
    saveRDS(olap, file = "summarized_overlaps.rds")
    saveRDS(deseq, file = "deseq_dataset.rds")
    saveRDS(edger, file = "edger_dgelist.rds")
    
    cat("Pipeline completed successfully. Outputs saved: read_counts.csv, summarized_overlaps.rds, deseq_dataset.rds, edger_dgelist.rds\n")
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

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_GENOMICALIGNMENTS_READ_COUNTING_FOR_DIFFERENTIAL_EXPRESSION",
      domain  = "bioconductor",
      declared_qc_steps = c("alignment/mapping QC"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_GENOMICALIGNMENTS_READ_COUNTING_FOR_DIFFERENTIAL_EXPRESSION":',
        paste0('        genomicalignments: ', as.character(packageVersion("genomicalignments")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_read_counting_for_differential_expression.csv versions.yml
    """
}

workflow BIOC_GENOMICALIGNMENTS_READ_COUNTING_FOR_DIFFERENTIAL_EXPRESSION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ bamfiles, features ] ]

    main:
    BIOC_GENOMICALIGNMENTS_READ_COUNTING_FOR_DIFFERENTIAL_EXPRESSION(ch_input)

    emit:
    tables   = BIOC_GENOMICALIGNMENTS_READ_COUNTING_FOR_DIFFERENTIAL_EXPRESSION.out.tables
    plots    = BIOC_GENOMICALIGNMENTS_READ_COUNTING_FOR_DIFFERENTIAL_EXPRESSION.out.plots
    objects  = BIOC_GENOMICALIGNMENTS_READ_COUNTING_FOR_DIFFERENTIAL_EXPRESSION.out.objects
    versions = BIOC_GENOMICALIGNMENTS_READ_COUNTING_FOR_DIFFERENTIAL_EXPRESSION.out.versions
}
