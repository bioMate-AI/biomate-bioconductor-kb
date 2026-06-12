#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: gscreend — pooled_screen_analysis
// Identify essential genes from pooled CRISPR screen raw count data by comparing gRNA abundances before and after selection.
// Input: raw_counts.txt
// Container: quay.io/biocontainers/bioconductor-gscreend:1.24.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SummarizedExperiment, gscreend
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Load raw count data and construct a SummarizedExperiment object with correct row and column metadata
//  * 2. [Input & Preparation] Create a PoolScreenExp object using createPoolScreenExp()
//  * 3. [Core Analysis] Run the main analysis pipeline using RunGscreend()
//  * 4. [Visualization & Output] Perform quality control using plotReplicateCorrelation() and plotModelParameters()
//  * 5. [Core Analysis] Extract gene-level results using ResultsTable()

nextflow.enable.dsl = 2

process BIOC_GSCREEND_POOLED_SCREEN_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    .bm_deps <- c("gscreend")
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
    library(gscreend)
    
    # 1. Load raw count data from the user-specified file
    # The file is expected to be a tab-separated text file in the working directory
    raw_counts <- read.table("raw_counts.txt", header = TRUE, sep = "\t", stringsAsFactors = FALSE)
    
    # Construct the counts matrix using the expected columns
    # Assuming column 1 is gRNA ID, column 2 is Gene, column 3 is library (T0), and columns 4+ are replicates (T1)
    counts_matrix <- as.matrix(raw_counts[, 3:ncol(raw_counts), drop = FALSE])
    
    # Construct row metadata (rowData)
    rowData <- data.frame(sgRNA_id = raw_counts[, 1],
                          gene = raw_counts[, 2])
    
    # Construct column metadata (colData)
    # T0 represents reference/library, T1 represents after proliferation
    colData <- data.frame(samplename = colnames(counts_matrix),
                          timepoint = c("T0", rep("T1", ncol(counts_matrix) - 1)))
    
    # Create the SummarizedExperiment object
    se <- SummarizedExperiment(assays = list(counts = counts_matrix),
                               rowData = rowData, 
                               colData = colData)
    
    # 2. Create a PoolScreenExp object
    pse <- createPoolScreenExp(se)
    
    # 3. Run the main analysis pipeline
    pse_an <- RunGscreend(pse)
    
    # 4. Perform quality control and save plots to PDF
    pdf("replicate_correlation.pdf", width = 6, height = 6)
    tryCatch({
        plotReplicateCorrelation(pse_an)
    }, error = function(e) {
        warning("Could not plot replicate correlation: ", e\$message)
    })
    dev.off()
    
    pdf("model_parameters.pdf", width = 6, height = 6)
    tryCatch({
        plotModelParameters(pse_an)
    }, error = function(e) {
        warning("Could not plot model parameters: ", e\$message)
    })
    dev.off()
    
    # 5. Extract gene-level results for negative selection (essential genes)
    res <- ResultsTable(pse_an, direction = "negative")
    
    # Write results to a CSV file
    write.csv(res, "essential_genes_results.csv", row.names = FALSE)
    
    # Save the analyzed PoolScreenExp object for downstream use
    saveRDS(pse_an, "gscreend_analysis_results.rds")

    writeLines(c(
        '"BIOC_GSCREEND_POOLED_SCREEN_ANALYSIS":',
        paste0('    gscreend: ', as.character(packageVersion('gscreend')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pooled_screen_analysis.csv versions.yml
    """
}

workflow BIOC_GSCREEND_POOLED_SCREEN_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ raw_counts.txt ] ]

    main:
    BIOC_GSCREEND_POOLED_SCREEN_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_GSCREEND_POOLED_SCREEN_ANALYSIS.out.tables
    plots    = BIOC_GSCREEND_POOLED_SCREEN_ANALYSIS.out.plots
    objects  = BIOC_GSCREEND_POOLED_SCREEN_ANALYSIS.out.objects
    versions = BIOC_GSCREEND_POOLED_SCREEN_ANALYSIS.out.versions
}
