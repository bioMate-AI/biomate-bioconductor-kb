#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: FGNet — gage_expression_to_network
// Perform gene set enrichment analysis on an expression matrix and build a functional network.
// Input: gse16873, geneLabels
// Container: quay.io/biocontainers/bioconductor-fgnet:3.44.0--r45hdfd78af_0
// R packages: FGNet, gage
// Bioconductor: 3.20 | R: 4.4
// Requires: FGNet, gage
// Visualizations: network plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Perform GSEA using fea_gage()
//  * 2. [Visualization & Output] Generate an HTML report using FGNet_report()
//  * 3. [Core Analysis] Convert results to incidence matrices using fea2incidMat()
//  * 4. [Visualization & Output] Plot the network using functionalNetwork()

nextflow.enable.dsl = 2

process BIOC_FGNET_GAGE_EXPRESSION_TO_NETWORK {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

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
    .bm_deps <- c("FGNet", "gage")
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
    library(FGNet)
    library(gage)
    
    # Read user input files from the working directory
    if (file.exists("gse16873.rds")) {
      gse16873 <- readRDS("gse16873.rds")
    } else if (file.exists("gse16873")) {
      gse16873 <- readRDS("gse16873")
    } else {
      stop("Error: gse16873 file not found in the working directory.")
    }
    
    if (file.exists("geneLabels.rds")) {
      geneLabels <- readRDS("geneLabels.rds")
    } else if (file.exists("geneLabels")) {
      geneLabels <- readRDS("geneLabels")
    } else {
      stop("Error: geneLabels file not found in the working directory.")
    }
    
    # Stage 1: Perform GSEA using fea_gage()
    feaResults_gage <- fea_gage(eset=gse16873,
                             refSamples=grep('HN',colnames(gse16873)),
                             compSamples=grep('DCIS',colnames(gse16873)),
                             geneLabels=geneLabels, annotations="REACTOME",
                             geneIdType="ENTREZID", organism="Hs")
    
    # Save the FEA results object
    saveRDS(feaResults_gage, "feaResults_gage.rds")
    
    # Stage 2: Generate an HTML report using FGNet_report()
    FGNet_report(feaResults_gage)
    
    # Stage 3: Convert results to incidence matrices using fea2incidMat()
    incidMat <- fea2incidMat(feaResults_gage)
    
    # Save incidence matrices object and export to CSV
    saveRDS(incidMat, "incidMat.rds")
    if (!is.null(incidMat\$clustersMatrix)) {
      write.csv(as.matrix(incidMat\$clustersMatrix), "clustersMatrix.csv", row.names=TRUE)
    }
    if (!is.null(incidMat\$metagroupsMatrix)) {
      write.csv(as.matrix(incidMat\$metagroupsMatrix), "metagroupsMatrix.csv", row.names=TRUE)
    }
    
    # Stage 4: Plot the network using functionalNetwork()
    # Save a static PDF version of the network for headless/non-interactive environments
    pdf("functional_network_static.pdf", width=10, height=10)
    tryCatch({
      functionalNetwork(incidMat, plotOutput="static")
    }, error = function(e) {
      warning("Static plotting failed: ", e\$message)
    })
    dev.off()
    
    # Execute the exact documented call (dynamic plot)
    # Wrapped in tryCatch as dynamic tkplot requires an active X11/display device
    tryCatch({
      functionalNetwork(incidMat, plotOutput="dynamic")
    }, error = function(e) {
      warning("Dynamic plotting (tkplot) skipped or failed (expected in non-interactive environments): ", e\$message)
    })

    writeLines(c(
        '"BIOC_FGNET_GAGE_EXPRESSION_TO_NETWORK":',
        paste0('    FGNet: ', as.character(packageVersion('FGNet')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gage_expression_to_network.csv versions.yml
    """
}

workflow BIOC_FGNET_GAGE_EXPRESSION_TO_NETWORK_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ gse16873, geneLabels ] ]

    main:
    BIOC_FGNET_GAGE_EXPRESSION_TO_NETWORK(ch_input)

    emit:
    tables   = BIOC_FGNET_GAGE_EXPRESSION_TO_NETWORK.out.tables
    plots    = BIOC_FGNET_GAGE_EXPRESSION_TO_NETWORK.out.plots
    objects  = BIOC_FGNET_GAGE_EXPRESSION_TO_NETWORK.out.objects
    versions = BIOC_FGNET_GAGE_EXPRESSION_TO_NETWORK.out.versions
}
