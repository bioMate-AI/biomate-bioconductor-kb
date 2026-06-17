#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: cTRAP — prepare_differential_expression_input
// Download ENCODE RNA-seq data, perform differential expression analysis, and prepare the t-statistics vector required for downstream cTRAP analyses.
// Input: cellLine, gene
// Container: quay.io/biocontainers/bioconductor-ctrap:1.28.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: cTRAP
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Download ENCODE knockdown metadata
//  * 2. [Input & Preparation] Load ENCODE samples
//  * 3. [Input & Preparation] Prepare gene expression counts
//  * 4. [Core Analysis] Convert gene identifiers to gene symbols
//  * 5. [Core Analysis] Perform differential expression analysis
//  * 6. [Core Analysis] Extract t-statistics and name them with gene symbols

nextflow.enable.dsl = 2

process BIOC_CTRAP_PREPARE_DIFFERENTIAL_EXPRESSION_INPUT {
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
    .bm_deps <- c("cTRAP")
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
    library(cTRAP)
    
    # Read user input files from the working directory
    if (!file.exists("cellLine") || !file.exists("gene")) {
      stop("Required input files 'cellLine' and/or 'gene' are missing in the working directory.")
    }
    
    cellLine <- trimws(readLines("cellLine", warn = FALSE)[1])
    gene <- trimws(readLines("gene", warn = FALSE)[1])
    
    message(paste("Processing cell line:", cellLine))
    message(paste("Target gene:", gene))
    
    # 1. Download ENCODE knockdown metadata
    message("Downloading ENCODE knockdown metadata...")
    ENCODEmetadata <- downloadENCODEknockdownMetadata(cellLine, gene)
    
    # Print metadata summary
    message("Metadata summary:")
    print(table(ENCODEmetadata\$`Experiment target`))
    message(paste("Unique experiment targets:", length(unique(ENCODEmetadata\$`Experiment target`))))
    
    # Save metadata to CSV
    write.csv(ENCODEmetadata, "ENCODE_metadata.csv", row.names = FALSE)
    
    # 2. Load ENCODE samples
    message("Loading ENCODE samples...")
    ENCODEsamples <- loadENCODEsamples(ENCODEmetadata)[[1]]
    
    # 3. Prepare gene expression counts
    message("Preparing gene expression counts...")
    counts <- prepareENCODEgeneExpression(ENCODEsamples)
    
    # Filter low coverage (at least 10 counts shared across two samples)
    minReads <- 10
    minSamples <- 2
    filter <- rowSums(counts[ , -c(1, 2)] >= minReads) >= minSamples
    counts <- counts[filter, ]
    
    # 4. Convert ENSEMBL identifier to gene symbol
    message("Converting gene identifiers...")
    counts\$gene_id <- convertGeneIdentifiers(counts\$gene_id)
    
    # Save prepared counts
    write.csv(counts, "prepared_counts.csv", row.names = FALSE)
    
    # 5. Perform differential gene expression analysis
    message("Performing differential expression analysis...")
    diffExpr <- performDifferentialExpression(counts)
    
    # Save full differential expression results
    write.csv(diffExpr, "differential_expression_results.csv", row.names = FALSE)
    
    # 6. Extract t-statistics and name them with gene symbols
    message("Extracting and naming t-statistics...")
    diffExprStat <- diffExpr\$t
    names(diffExprStat) <- diffExpr\$Gene_symbol
    
    # Save t-statistics vector as RDS (required input for downstream cTRAP analyses)
    saveRDS(diffExprStat, "diffExprStat.rds")
    
    # Generate a diagnostic plot of the t-statistics distribution
    pdf("t_statistics_distribution.pdf")
    hist(diffExprStat, breaks = 100, 
         main = paste("t-statistics Distribution\n", gene, "Knockdown in", cellLine),
         xlab = "t-statistic", col = "skyblue", border = "white")
    abline(v = 0, col = "red", lty = 2, lwd = 2)
    dev.off()
    
    message("Pipeline completed successfully. Outputs written to working directory.")

    writeLines(c(
        '"BIOC_CTRAP_PREPARE_DIFFERENTIAL_EXPRESSION_INPUT":',
        paste0('    cTRAP: ', as.character(packageVersion('cTRAP')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_prepare_differential_expression_input.csv versions.yml
    """
}

workflow BIOC_CTRAP_PREPARE_DIFFERENTIAL_EXPRESSION_INPUT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ cellLine, gene ] ]

    main:
    BIOC_CTRAP_PREPARE_DIFFERENTIAL_EXPRESSION_INPUT(ch_input)

    emit:
    tables   = BIOC_CTRAP_PREPARE_DIFFERENTIAL_EXPRESSION_INPUT.out.tables
    plots    = BIOC_CTRAP_PREPARE_DIFFERENTIAL_EXPRESSION_INPUT.out.plots
    objects  = BIOC_CTRAP_PREPARE_DIFFERENTIAL_EXPRESSION_INPUT.out.objects
    versions = BIOC_CTRAP_PREPARE_DIFFERENTIAL_EXPRESSION_INPUT.out.versions
}
