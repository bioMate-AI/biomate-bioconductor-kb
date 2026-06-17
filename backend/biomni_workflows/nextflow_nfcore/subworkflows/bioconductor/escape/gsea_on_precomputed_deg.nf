#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: escape — gsea_on_precomputed_deg
// Perform classical GSEA on precomputed differential expression results using ranked gene lists and visualize the output.
// Input: deg_results.csv, gene_sets.rds
// Container: quay.io/biocontainers/bioconductor-escape:2.6.2--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: escape, ggplot2
// Visualizations: enrichment plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run GSEA on the ranked differential expression results using enrichIt
//  * 2. [Visualization & Output] Visualize GSEA results using enrichItPlot to generate bar, dot, or cnet plots

nextflow.enable.dsl = 2

process BIOC_ESCAPE_GSEA_ON_PRECOMPUTED_DEG {
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
    .bm_deps <- c("escape", "ggplot2")
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
    suppressPackageStartupMessages({
      library(escape)
      library(ggplot2)
    })
    
    # 1. Read User Input Files
    # Read precomputed DEG results (e.g., from FindMarkers, DESeq2, or edgeR)
    # We assume the first column contains gene symbols (row names)
    DEG.markers <- read.csv("deg_results.csv", row.names = 1)
    
    # Read the gene sets (list or GSEABase GeneSetCollection object)
    escape.gene.sets <- readRDS("gene_sets.rds")
    
    # 2. Run GSEA on the ranked differential expression results using enrichIt
    GSEA.results <- enrichIt(input.data = DEG.markers, 
                             gene.sets = escape.gene.sets, 
                             ranking_fun = "signed_log10_p")               
    
    # Save the GSEA results table
    write.csv(GSEA.results, "gsea_results.csv", row.names = FALSE)
    saveRDS(GSEA.results, "gsea_results.rds")
    
    # 3. Visualize GSEA results using enrichItPlot and save to PDF
    pdf("gsea_plots.pdf", width = 10, height = 8)
    
    ## (1) Bar plot – 20 most significant per database
    p1 <- enrichItPlot(GSEA.results)               
    print(p1)
    
    ## (2) Dot plot – coloured by –log10 padj, sized by core-hits
    p2 <- enrichItPlot(GSEA.results, "dot", top = 10) 
    print(p2)
    
    ## (3) C-net plot – network of pathways ↔ leading-edge genes
    p3 <- enrichItPlot(GSEA.results, "cnet", top = 5)
    print(p3)
    
    dev.off()

    writeLines(c(
        '"BIOC_ESCAPE_GSEA_ON_PRECOMPUTED_DEG":',
        paste0('    escape: ', as.character(packageVersion('escape')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gsea_on_precomputed_deg.csv versions.yml
    """
}

workflow BIOC_ESCAPE_GSEA_ON_PRECOMPUTED_DEG_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ deg_results.csv, gene_sets.rds ] ]

    main:
    BIOC_ESCAPE_GSEA_ON_PRECOMPUTED_DEG(ch_input)

    emit:
    tables   = BIOC_ESCAPE_GSEA_ON_PRECOMPUTED_DEG.out.tables
    plots    = BIOC_ESCAPE_GSEA_ON_PRECOMPUTED_DEG.out.plots
    objects  = BIOC_ESCAPE_GSEA_ON_PRECOMPUTED_DEG.out.objects
    versions = BIOC_ESCAPE_GSEA_ON_PRECOMPUTED_DEG.out.versions
}
