#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: graphite — spia_analysis
// Run Signaling Pathway Impact Analysis (SPIA) on differential gene expression data using graphite pathways.
// Input: top.txt, hgu133plus2.db
// Container: quay.io/biocontainers/bioconductor-graphite:1.56.0--r45hdfd78af_0
// R packages: AnnotationDbi, graph, graphite, hgu133plus2.db, SPIA, topologyGSA
// Bioconductor: 3.20 | R: 4.4
// Requires: AnnotationDbi, graphite, hgu133plus2.db
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Map probe IDs to Entrez IDs and format with the "ENTREZID:" prefix
//  * 2. [Input & Preparation] Extract logFC for significant genes and define the background gene list
//  * 3. [Input & Preparation] Load KEGG pathways and convert identifiers to "ENTREZID"
//  * 4. [Input & Preparation] Prepare SPIA input files using prepareSPIA
//  * 5. [Core Analysis] Run SPIA using runSPIA

nextflow.enable.dsl = 2

process BIOC_GRAPHITE_SPIA_ANALYSIS {
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
    .bm_deps <- c("AnnotationDbi", "graph", "graphite", "hgu133plus2.db", "SPIA", "topologyGSA")
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
    library(graphite)
    library(SPIA)
    library(AnnotationDbi)
    
    # Load the annotation database. 
    # If hgu133plus2.db is provided as a SQLite file in the working directory, load it using loadDb.
    # Otherwise, attempt to load it as an installed Bioconductor package.
    if (file.exists("hgu133plus2.db")) {
      hgu133plus2.db <- loadDb("hgu133plus2.db")
    } else {
      library(hgu133plus2.db)
    }
    
    # Read the user input differential expression results
    top <- read.table("top.txt", header = TRUE, sep = "\t", stringsAsFactors = FALSE)
    
    # 1. Map probe IDs to Entrez IDs and format with the "ENTREZID:" prefix
    top\$ENTREZ <- mapIds(hgu133plus2.db,
                         top\$ID, "ENTREZID", "PROBEID", multiVals = "first")
    top <- top[!is.na(top\$ENTREZ) & !duplicated(top\$ENTREZ), ]
    top\$ENTREZ <- paste("ENTREZID", top\$ENTREZ, sep = ":")
    tg1 <- top[top\$adj.P.Val < 0.05, ]
    
    # 2. Extract logFC for significant genes and define the background gene list
    DE_genes = tg1\$logFC
    names(DE_genes) <- tg1\$ENTREZ
    ALL_genes <- top\$ENTREZ
    
    # 3. Load KEGG pathways and convert identifiers to "ENTREZID"
    kegg <- pathways("hsapiens", "kegg")
    kegg <- convertIdentifiers(kegg, "ENTREZID")
    
    # 4. Prepare SPIA input files using prepareSPIA
    prepareSPIA(kegg, "keggEx")
    
    # 5. Run SPIA using runSPIA
    res <- runSPIA(de = DE_genes, all = ALL_genes, "keggEx")
    
    # Write meaningful output files
    write.csv(res, "spia_results.csv", row.names = FALSE)
    saveRDS(res, "spia_results.rds")
    
    # Clean up temporary SPIA files created in the working directory
    if (file.exists("keggExSPIA.RData")) {
      file.remove("keggExSPIA.RData")
    }

    writeLines(c(
        '"BIOC_GRAPHITE_SPIA_ANALYSIS":',
        paste0('    graphite: ', as.character(packageVersion('graphite')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_spia_analysis.csv versions.yml
    """
}

workflow BIOC_GRAPHITE_SPIA_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ top.txt, hgu133plus2.db ] ]

    main:
    BIOC_GRAPHITE_SPIA_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_GRAPHITE_SPIA_ANALYSIS.out.tables
    plots    = BIOC_GRAPHITE_SPIA_ANALYSIS.out.plots
    objects  = BIOC_GRAPHITE_SPIA_ANALYSIS.out.objects
    versions = BIOC_GRAPHITE_SPIA_ANALYSIS.out.versions
}
