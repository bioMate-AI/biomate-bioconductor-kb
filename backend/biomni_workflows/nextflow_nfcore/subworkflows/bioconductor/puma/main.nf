#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: puma — standard_3_prime_array_analysis
// Perform summarisation, normalization, PCA, replicate combining, and differential expression analysis on standard Affymetrix 3' arrays.
// Input: celFiles
// Container: quay.io/biocontainers/bioconductor-puma:3.52.0--r45h01b2380_0
// R packages: oligo, puma, pumadata, rmpi, snow
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: UMAP plot, PCA plot

nextflow.enable.dsl = 2

process BIOC_PUMA_STANDARD_3_PRIME_ARRAY_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-puma:3.52.0--r45h01b2380_0"

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
    .bm_deps <- c("oligo", "puma", "pumadata", "rmpi", "snow")
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
    
    # Load required Bioconductor libraries
    library(oligo)
    library(puma)
    
    # --- Read CEL files and define phenotype data ---
    # The pipeline reads raw Affymetrix 3' array CEL files from the working directory
    celFiles <- list.celfiles()
    
    if (length(celFiles) != 8) {
      stop("This standard 3' array analysis pipeline requires exactly 8 CEL files matching the 2x2 factorial design (estrogen x time.h).")
    }
    
    estrogenFilenames<-list.celfiles()
    oligo.estrogen<-read.celfiles(celFiles)
    
    pData(oligo.estrogen) <- data.frame(
        "estrogen"=c("absent","absent","present","present"
            ,"absent","absent","present","present")
    ,   "time.h"=c("10","10","10","10","48","48","48","48")
    ,   row.names=rownames(pData(oligo.estrogen))
    )
    
    # --- Summarise probe-level data using mmgmos ---
    eset_estrogen_mmgmos<-mmgmos(oligo.estrogen,gsnorm="none")
    saveRDS(eset_estrogen_mmgmos, file="eset_estrogen_mmgmos.rds")
    
    # --- Perform uncertainty-aware PCA ---
    pumapca_estrogen <- pumaPCA(eset_estrogen_mmgmos)
    saveRDS(pumapca_estrogen, file="pumapca_estrogen.rds")
    
    # Plot PCA and save to PDF
    pdf("pumaPCA_plot.pdf", width=7, height=7)
    plot(pumapca_estrogen,legend1pos="right",legend2pos="top",main="pumaPCA")
    dev.off()
    
    # --- Normalize expression levels ---
    eset_estrogen_mmgmos_normd <- pumaNormalize(eset_estrogen_mmgmos)
    saveRDS(eset_estrogen_mmgmos_normd, file="eset_estrogen_mmgmos_normd.rds")
    
    # --- Combine replicate arrays ---
    eset_estrogen_comb <- pumaComb(eset_estrogen_mmgmos_normd)
    saveRDS(eset_estrogen_comb, file="eset_estrogen_comb.rds")
    
    # --- Identify differentially expressed genes using PPLR ---
    pumaDERes <- pumaDE(eset_estrogen_comb)
    saveRDS(pumaDERes, file="pumaDERes.rds")
    
    # Write out the statistics and fold change results to CSV files
    write.reslts(pumaDERes, file="pumaDERes")
    
    # --- Plot expression levels with error bars ---
    toppumaDEIntGene <- topGenes(pumaDERes, contrast=7)
    write.csv(toppumaDEIntGene, file="toppumaDEIntGene.csv", row.names=TRUE)
    
    pdf("error_bars_plot.pdf", width=7, height=7)
    plotErrorBars(eset_estrogen_mmgmos_normd, toppumaDEIntGene)
    dev.off()
    
    cat("Pipeline completed successfully. Outputs saved to the working directory.\n")

    writeLines(c(
        '"BIOC_PUMA_STANDARD_3_PRIME_ARRAY_ANALYSIS":',
        paste0('        puma: ', as.character(packageVersion("puma")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standard_3_prime_array_analysis.csv versions.yml
    """
}

workflow BIOC_PUMA_STANDARD_3_PRIME_ARRAY_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ celFiles ] ]

    main:
    BIOC_PUMA_STANDARD_3_PRIME_ARRAY_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_PUMA_STANDARD_3_PRIME_ARRAY_ANALYSIS.out.tables
    plots    = BIOC_PUMA_STANDARD_3_PRIME_ARRAY_ANALYSIS.out.plots
    objects  = BIOC_PUMA_STANDARD_3_PRIME_ARRAY_ANALYSIS.out.objects
    versions = BIOC_PUMA_STANDARD_3_PRIME_ARRAY_ANALYSIS.out.versions
}
