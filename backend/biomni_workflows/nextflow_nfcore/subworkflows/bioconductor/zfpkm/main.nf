#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: zFPKM — zfpkm_active_gene_filtering
// Perform zFPKM transformation on gene-level RNA-seq FPKM data, visualize the distribution fit, and filter for active genes.
// Input: SummarizedExperiment object containing FPKM and raw count assays, along with sample metadata.
// Container: quay.io/biocontainers/bioconductor-zfpkm:1.32.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SummarizedExperiment, dplyr, tidyr, zFPKM
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Compute zFPKM scores using zFPKM()
//  * 2. [Visualization & Output] Plot the Gaussian fit using zFPKMPlot()
//  * 3. [Core Analysis] Filter for active genes with median zFPKM > -3 within treatment groups

nextflow.enable.dsl = 2

process BIOC_ZFPKM_ZFPKM_ACTIVE_GENE_FILTERING {
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
    .bm_deps <- c("zFPKM", "dplyr", "tidyr", "SummarizedExperiment")
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
    library(zFPKM)
    library(SummarizedExperiment)
    library(dplyr)
    library(tidyr)
    
    # 1. Read the user-provided SummarizedExperiment object
    # The input file "se.rds" must exist in the working directory and contain
    # FPKM and raw count assays, along with sample metadata (including 'condition' and 'sample_id').
    se <- readRDS("se.rds")
    
    # 2. Compute zFPKM scores using zFPKM()
    assay(se, "zfpkm") <- zFPKM(se)
    
    # 3. Plot the Gaussian fit and save to PDF
    pdf("zfpkm_fit_plot.pdf", width=8, height=6)
    print(zFPKMPlot(se))
    invisible(dev.off())
    
    # 4. Filter for active genes with median zFPKM > -3 within treatment groups
    # This code is reproduced EXACTLY as documented in the package vignette.
    activeGenes <- as.data.frame(assay(se, "zfpkm")) %>%
      mutate(gene=rownames(assay(se, "zfpkm"))) %>%
      gather(sample_id, zfpkm, -gene) %>%
      left_join(select(as.data.frame(colData(se)), sample_id, condition), by="sample_id") %>%
      group_by(gene, condition) %>%
      summarize(median_zfpkm=median(zfpkm)) %>%
      ungroup() %>%
      mutate(active=(median_zfpkm > -3)) %>%
      filter(active) %>%
      select(gene) %>%
      distinct()
    
    # 5. Save the results to output files
    write.csv(activeGenes, "active_genes.csv", row.names=FALSE)
    saveRDS(se, "se_with_zfpkm.rds")

    writeLines(c(
        '"BIOC_ZFPKM_ZFPKM_ACTIVE_GENE_FILTERING":',
        paste0('    zFPKM: ', as.character(packageVersion('zFPKM')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_zfpkm_active_gene_filtering.csv versions.yml
    """
}

workflow BIOC_ZFPKM_ZFPKM_ACTIVE_GENE_FILTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ SummarizedExperiment object containing FPKM and raw count assays, along with sample metadata. ] ]

    main:
    BIOC_ZFPKM_ZFPKM_ACTIVE_GENE_FILTERING(ch_input)

    emit:
    tables   = BIOC_ZFPKM_ZFPKM_ACTIVE_GENE_FILTERING.out.tables
    plots    = BIOC_ZFPKM_ZFPKM_ACTIVE_GENE_FILTERING.out.plots
    objects  = BIOC_ZFPKM_ZFPKM_ACTIVE_GENE_FILTERING.out.objects
    versions = BIOC_ZFPKM_ZFPKM_ACTIVE_GENE_FILTERING.out.versions
}
