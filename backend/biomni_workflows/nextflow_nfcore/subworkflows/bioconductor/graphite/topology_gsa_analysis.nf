#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: graphite — topology_gsa_analysis
// Test pathway deregulation using graphical models (topologyGSA) on gene expression data.
// Input: y1.txt, y2.txt
// Container: quay.io/biocontainers/bioconductor-graphite:1.56.0--r45hdfd78af_0
// R packages: graphite, topologyGSA
// Bioconductor: 3.20 | R: 4.4
// Requires: graphite, topologyGSA
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Format expression matrix column names with the "SYMBOL:" prefix
//  * 2. [Input & Preparation] Load KEGG pathways and convert identifiers to "SYMBOL"
//  * 3. [Core Analysis] Run topologyGSA variance test using runTopologyGSA

nextflow.enable.dsl = 2

process BIOC_GRAPHITE_TOPOLOGY_GSA_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

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
    .bm_deps <- c("graphite", "topologyGSA")
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
    library(graphite)
    library(topologyGSA)
    
    # Read user input files from the working directory
    # These files are expected to have genes as columns and samples as rows,
    # with the first column containing sample IDs.
    y1 <- as.matrix(read.table("y1.txt", header = TRUE, sep = "\t", row.names = 1, check.names = FALSE))
    y2 <- as.matrix(read.table("y2.txt", header = TRUE, sep = "\t", row.names = 1, check.names = FALSE))
    
    # 1. Format expression matrix column names with the "SYMBOL:" prefix
    colnames(y1) <- paste("SYMBOL", colnames(y1), sep = ":")
    colnames(y2) <- paste("SYMBOL", colnames(y2), sep = ":")
    
    # 2. Load KEGG pathways and convert identifiers to "SYMBOL"
    kegg <- pathways("hsapiens", "kegg")
    p <- convertIdentifiers(kegg[["Fc epsilon RI signaling pathway"]], "SYMBOL")
    
    # 3. Run topologyGSA variance test using runTopologyGSA
    res <- runTopologyGSA(p, "var", y1, y2, 0.05)
    
    # Write named output files for the meaningful results
    # Save the raw result object
    saveRDS(res, "topology_gsa_result.rds")
    
    # Save the printed text summary of the test
    sink("topology_gsa_result.txt")
    print(res)
    sink()
    
    # Attempt to format and save a CSV table of the test statistics
    tryCatch({
      if (inherits(res, "htest")) {
        res_df <- data.frame(
          statistic = if (!is.null(res\$statistic)) res\$statistic else NA,
          parameter = if (!is.null(res\$parameter)) paste(res\$parameter, collapse = ";") else NA,
          p.value = if (!is.null(res\$p.value)) res\$p.value else NA,
          method = if (!is.null(res\$method)) res\$method else NA,
          stringsAsFactors = FALSE
        )
        write.csv(res_df, "topology_gsa_result.csv", row.names = FALSE)
      }
    }, error = function(e) {
      # Fallback if the result structure differs
    })

    writeLines(c(
        '"BIOC_GRAPHITE_TOPOLOGY_GSA_ANALYSIS":',
        paste0('    graphite: ', as.character(packageVersion('graphite')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_topology_gsa_analysis.csv versions.yml
    """
}

workflow BIOC_GRAPHITE_TOPOLOGY_GSA_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ y1.txt, y2.txt ] ]

    main:
    BIOC_GRAPHITE_TOPOLOGY_GSA_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_GRAPHITE_TOPOLOGY_GSA_ANALYSIS.out.tables
    plots    = BIOC_GRAPHITE_TOPOLOGY_GSA_ANALYSIS.out.plots
    objects  = BIOC_GRAPHITE_TOPOLOGY_GSA_ANALYSIS.out.objects
    versions = BIOC_GRAPHITE_TOPOLOGY_GSA_ANALYSIS.out.versions
}
