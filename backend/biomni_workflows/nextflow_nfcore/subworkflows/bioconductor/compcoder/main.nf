#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: compcodeR — standard_rnaseq_comparison
// Format user's count matrix and sample annotations into a compData object, run multiple DE methods, and compare their performance.
// Input: count.matrix, sample.annot
// Container: quay.io/biocontainers/bioconductor-compcoder:1.46.0--r45hdfd78af_0
// R packages: ape, compcodeR
// Bioconductor: 3.20 | R: 4.4
// Requires: compcodeR
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
