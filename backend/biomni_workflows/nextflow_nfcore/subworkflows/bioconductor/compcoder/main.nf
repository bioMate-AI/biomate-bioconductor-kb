#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: compcodeR — standard_rnaseq_comparison
// Format user's count matrix and sample annotations into a compData object, run multiple DE methods, and compare their performance.
// Input: count.matrix, sample.annot
// Container: quay.io/biocontainers/bioconductor-compcoder:1.46.0--r45hdfd78af_0
// R packages: ape, compcodeR
// Bioconductor: 3.20 | R: 4.4
// Requires: compcodeR
// QC: voom mean-variance modelling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Create a compData object using the compData constructor. 2. Validate the object using check_compData. 3. Save the object to an RDS

nextflow.enable.dsl = 2

process BIOC_COMPCODER_STANDARD_RNASEQ_COMPARISON {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("ape", "compcodeR")
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
        library(compcodeR)
        
        # Helper to read table robustly
        read_input_table <- function(filepath, as_matrix = FALSE) {
          if (!file.exists(filepath)) {
            stop(paste("Required input file", filepath, "not found in the working directory."))
          }
          # Try reading as RDS first
          obj <- tryCatch(readRDS(filepath), error = function(e) NULL)
          if (!is.null(obj)) {
            if (as_matrix) return(as.matrix(obj))
            return(as.data.frame(obj))
          }
          # Try reading as table
          df <- read.table(filepath, header = TRUE, row.names = 1, check.names = FALSE, sep = "")
          if (as_matrix) return(as.matrix(df))
          return(df)
        }
        
        # Read user inputs
        count.matrix <- read_input_table("count.matrix", as_matrix = TRUE)
        sample.annot <- read_input_table("sample.annot", as_matrix = FALSE)
        
        # Ensure sample.annot has 'condition' column
        if (!"condition" %in% colnames(sample.annot)) {
          if (ncol(sample.annot) == 1) {
            colnames(sample.annot) <- "condition"
          } else {
            stop("sample.annot must contain a 'condition' column.")
          }
        }
        
        # Format user's count matrix and sample annotations into a compData object
        info.parameters <- list(dataset = "B_625_625", uID = "123456")
        cpd <- compData(count.matrix = count.matrix, 
                        sample.annotations = sample.annot, 
                        info.parameters = info.parameters)
        
        # Validate the object
        check_compData(cpd)
        
        # Save the object to RDS files
        saveRDS(cpd, "saveddata.rds")
        saveRDS(cpd, "B_625_625_5spc_repl1.rds")
        
        # Run multiple DE methods
        runDiffExp(data.file = "B_625_625_5spc_repl1.rds", result.extent = "voom.limma", Rmdfunction = "voom.limma.createRmd", output.directory = ".", norm.method = "TMM")
        runDiffExp(data.file = "B_625_625_5spc_repl1.rds", result.extent = "edgeR.exact", Rmdfunction = "edgeR.exact.createRmd", output.directory = ".", norm.method = "TMM", trend.method = "movingave", disp.type = "tagwise")
        runDiffExp(data.file = "B_625_625_5spc_repl1.rds", result.extent = "ttest", Rmdfunction = "ttest.createRmd", output.directory = ".", norm.method = "TMM")
        
        # Compare their performance
        file.table <- data.frame(input.files = c("B_625_625_5spc_repl1_voom.limma.rds", "B_625_625_5spc_repl1_ttest.rds", "B_625_625_5spc_repl1_edgeR.exact.rds"), stringsAsFactors = FALSE)
        parameters <- list(incl.nbr.samples = NULL, incl.replicates = NULL, incl.dataset = "B_625_625", incl.de.methods = NULL, fdr.threshold = 0.05, tpr.threshold = 0.05, typeI.threshold = 0.05, ma.threshold = 0.05, fdc.maxvar = 1500, overlap.threshold = 0.05, fracsign.threshold = 0.05, comparisons = c("ma", "correlation"))
        runComparison(file.table = file.table, parameters = parameters, output.directory = ".")
        
        # Copy the generated HTML report to a predictable name
        html_files <- list.files(".", pattern = "^compcodeR_report_.*\\\\.html\$", full.names = TRUE)
        if (length(html_files) > 0) {
          html_files <- html_files[order(file.info(html_files)\$mtime, decreasing = TRUE)]
          file.copy(html_files[1], "compcodeR_report.html", overwrite = TRUE)
        }
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # voom — limma EList\$weights present, range > 0 (Law 2014 GB).
    .voom_w_range <- NA_real_
    for (.voom_rds in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
      .voom_obj <- tryCatch(readRDS(.voom_rds), error = function(e) NULL)
      if (!is.null(.voom_obj) && inherits(.voom_obj, "EList")) {
        .voom_w <- tryCatch(.voom_obj\$weights, error = function(e) NULL)
        if (!is.null(.voom_w) && length(.voom_w) > 0) {
          .voom_w_range <- round(diff(range(.voom_w, na.rm = TRUE)), 4); break
        }
      }
    }
    .gates_by_label[["voom mean-variance modelling"]] <- list(
      gate_row = "bioc_voom_mean_variance",
      metric_name = "voom_weight_range",
      metric_value = .voom_w_range,
      passes = isTRUE(is.finite(.voom_w_range) && .voom_w_range > 0),
      status = if (is.finite(.voom_w_range)) "computed (EList\$weights range)"
               else "not_computed (no limma EList .rds artifact present)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_COMPCODER_STANDARD_RNASEQ_COMPARISON",
      domain  = "bioconductor",
      declared_qc_steps = c("voom mean-variance modelling"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_COMPCODER_STANDARD_RNASEQ_COMPARISON":',
        paste0('    compcodeR: ', as.character(packageVersion('compcodeR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standard_rnaseq_comparison.csv versions.yml
    """
}

workflow BIOC_COMPCODER_STANDARD_RNASEQ_COMPARISON_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ count.matrix, sample.annot ] ]

    main:
    BIOC_COMPCODER_STANDARD_RNASEQ_COMPARISON(ch_input)

    emit:
    tables   = BIOC_COMPCODER_STANDARD_RNASEQ_COMPARISON.out.tables
    plots    = BIOC_COMPCODER_STANDARD_RNASEQ_COMPARISON.out.plots
    objects  = BIOC_COMPCODER_STANDARD_RNASEQ_COMPARISON.out.objects
    versions = BIOC_COMPCODER_STANDARD_RNASEQ_COMPARISON.out.versions
}
