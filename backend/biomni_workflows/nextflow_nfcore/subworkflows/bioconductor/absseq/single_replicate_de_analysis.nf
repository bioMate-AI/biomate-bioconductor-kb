#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ABSSeq — single_replicate_de_analysis
// Perform differential expression analysis on RNA-Seq data when no replicates are available.
// Input: counts_no_replicates.tsv
// Container: quay.io/biocontainers/bioconductor-absseq:1.64.0--r45hdfd78af_0
// R packages: ABSSeq
// Bioconductor: 3.20 | R: 4.4
// Requires: ABSSeq
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Construct the ABSDataSet object using the two-column count matrix and a two-level group factor
//  * 2. [Core Analysis] Run the ABSSeq pipeline, which automatically handles single-replicate parameter estimation
//  * 3. [Core Analysis] Extract the differential expression results

nextflow.enable.dsl = 2

process BIOC_ABSSEQ_SINGLE_REPLICATE_DE_ANALYSIS {
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
    .bm_deps <- c("ABSSeq")
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
    library(ABSSeq)
    
    # Define input file
    input_file <- "counts_no_replicates.tsv"
    
    # Check if input file exists
    if (!file.exists(input_file)) {
      stop(paste("Error: Input file", input_file, "not found in the working directory."))
    }
    
    # Read the raw integer counts matrix
    counts_matrix <- as.matrix(read.table(input_file, header = TRUE, sep = "\t", row.names = 1, check.names = FALSE))
    
    # Ensure counts are integers
    counts_matrix <- round(counts_matrix)
    
    # Verify that there are exactly two columns
    if (ncol(counts_matrix) != 2) {
      stop("Error: The input count matrix must contain exactly two columns for single-replicate analysis.")
    }
    
    # 1. Construct the ABSDataSet object using the two-column count matrix and a two-level group factor
    obj <- ABSDataSet(counts_matrix, factor(c(1,2)))
    
    # 2. Run the ABSSeq pipeline, which automatically handles single-replicate parameter estimation
    obj <- ABSSeq(obj)
    
    # 3. Extract the differential expression results
    res <- results(obj, c("Amean","Bmean","foldChange","pvalue","adj.pvalue"))
    
    # Print head of results to console
    print(head(res))
    
    # Write outputs
    write.csv(res, file = "de_results_single_replicate.csv", row.names = TRUE)
    saveRDS(obj, file = "absseq_object.rds")
    
    # Optional diagnostic plot
    tryCatch({
      pdf("difftobase_plot.pdf")
      plotDifftoBase(obj)
      dev.off()
    }, error = function(e) {
      message("Diagnostic plot generation skipped or failed: ", e\$message)
    })

    writeLines(c(
        '"BIOC_ABSSEQ_SINGLE_REPLICATE_DE_ANALYSIS":',
        paste0('    ABSSeq: ', as.character(packageVersion('ABSSeq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_replicate_de_analysis.csv versions.yml
    """
}

workflow BIOC_ABSSEQ_SINGLE_REPLICATE_DE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ counts_no_replicates.tsv ] ]

    main:
    BIOC_ABSSEQ_SINGLE_REPLICATE_DE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_ABSSEQ_SINGLE_REPLICATE_DE_ANALYSIS.out.tables
    plots    = BIOC_ABSSEQ_SINGLE_REPLICATE_DE_ANALYSIS.out.plots
    objects  = BIOC_ABSSEQ_SINGLE_REPLICATE_DE_ANALYSIS.out.objects
    versions = BIOC_ABSSEQ_SINGLE_REPLICATE_DE_ANALYSIS.out.versions
}
