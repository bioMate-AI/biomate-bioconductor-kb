#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: M3C — regularised_consensus_clustering
// Run fast regularized consensus clustering using a penalty term to find the optimal K without Monte Carlo simulations.
// Input: mydata
// Container: quay.io/biocontainers/bioconductor-m3c:1.32.0--r45hdfd78af_0
// R packages: M3C
// Bioconductor: 3.20 | R: 4.4
// Requires: M3C
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run M3C with regularized consensus clustering (method=2) and lambda tuning
//  * 2. [Visualization & Output] Plot the Penalized Cluster Stability Index (PCSI) or Entropy curves to identify the optimal K

nextflow.enable.dsl = 2

process BIOC_M3C_REGULARISED_CONSENSUS_CLUSTERING {
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
    .bm_deps <- c("M3C")
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
    library(M3C)
    
    # Read user input file 'mydata' from the working directory
    # The file can be named 'mydata', 'mydata.csv', 'mydata.tsv', or 'mydata.txt'
    if (file.exists("mydata")) {
      mydata <- read.csv("mydata", row.names = 1, check.names = FALSE)
    } else if (file.exists("mydata.csv")) {
      mydata <- read.csv("mydata.csv", row.names = 1, check.names = FALSE)
    } else if (file.exists("mydata.tsv")) {
      mydata <- read.delim("mydata.tsv", row.names = 1, check.names = FALSE)
    } else if (file.exists("mydata.txt")) {
      mydata <- read.table("mydata.txt", header = TRUE, row.names = 1, check.names = FALSE)
    } else {
      stop("Required input file 'mydata' (or with .csv/.tsv/.txt extension) not found in the working directory.")
    }
    
    # Ensure data is in matrix format for M3C
    mydata <- as.matrix(mydata)
    
    # -----------------------------------------------------------------------------
    # Stage 1: Run M3C with regularized consensus clustering (method=2) and PAC objective
    # -----------------------------------------------------------------------------
    res <- M3C(mydata, method = 2, objective='PAC',fsize=8, lthick=1, dotsize=1.25)
    
    # Save the PCSI plot for the PAC objective
    pdf("pcsi_pac_plot.pdf")
    print(res\$plots[[3]])
    dev.off()
    
    # Save scores and results object
    write.csv(res\$scores, "res_pac_scores.csv", row.names = FALSE)
    saveRDS(res, "res_pac.rds")
    
    # -----------------------------------------------------------------------------
    # Stage 2: Run M3C with regularized consensus clustering (method=2) and default Entropy objective
    # -----------------------------------------------------------------------------
    res <- M3C(mydata, method = 2,fsize=8, lthick=1, dotsize=1.25)
    
    # Save the Entropy plot
    pdf("entropy_plot.pdf")
    print(res\$plots[[2]])
    dev.off()
    
    # Save the PCSI plot for the Entropy objective
    pdf("pcsi_entropy_plot.pdf")
    print(res\$plots[[3]])
    dev.off()
    
    # Save scores and results object
    write.csv(res\$scores, "res_entropy_scores.csv", row.names = FALSE)
    saveRDS(res, "res_entropy.rds")

    writeLines(c(
        '"BIOC_M3C_REGULARISED_CONSENSUS_CLUSTERING":',
        paste0('    M3C: ', as.character(packageVersion('M3C')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_regularised_consensus_clustering.csv versions.yml
    """
}

workflow BIOC_M3C_REGULARISED_CONSENSUS_CLUSTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ mydata ] ]

    main:
    BIOC_M3C_REGULARISED_CONSENSUS_CLUSTERING(ch_input)

    emit:
    tables   = BIOC_M3C_REGULARISED_CONSENSUS_CLUSTERING.out.tables
    plots    = BIOC_M3C_REGULARISED_CONSENSUS_CLUSTERING.out.plots
    objects  = BIOC_M3C_REGULARISED_CONSENSUS_CLUSTERING.out.objects
    versions = BIOC_M3C_REGULARISED_CONSENSUS_CLUSTERING.out.versions
}
