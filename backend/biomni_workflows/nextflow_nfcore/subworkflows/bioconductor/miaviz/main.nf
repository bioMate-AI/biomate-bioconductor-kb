#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: miaViz — abundance_plotting
// Plot taxonomic abundance by rank, subset by prevalence, and combine with sample metadata.
// Input: GlobalPatterns
// Container: quay.io/biocontainers/bioconductor-miaviz:1.18.0--r45hdfd78af_0
// R packages: dplyr, ggplot2, mia, miaTime, miaViz, patchwork, scater
// Bioconductor: 3.20 | R: 4.4
// Requires: ggplot2, mia, miaViz, patchwork
// Visualizations: abundance plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Transform assay to relative abundance
//  * 2. [Visualization & Output] Plot abundance by taxonomic rank
//  * 3. [Visualization & Output] Agglomerate and plot abundance
//  * 4. [Visualization & Output] Filter by prevalent taxa and plot
//  * 5. [Visualization & Output] Combine abundance plot with sample metadata using patchwork

nextflow.enable.dsl = 2

process BIOC_MIAVIZ_ABUNDANCE_PLOTTING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-metagenomics:3.20-deps"

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
    .bm_deps <- c("dplyr", "ggplot2", "mia", "miaTime", "miaViz", "patchwork", "scater", "SummarizedExperiment")
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
    library(mia)
    library(SummarizedExperiment)
    library(miaViz)
    library(patchwork)
    library(ggplot2)
    
    # 1. Read the input TreeSummarizedExperiment object from the working directory
    # The user-provided file is expected to be named "GlobalPatterns.rds"
    GlobalPatterns <- readRDS("GlobalPatterns.rds")
    
    # 2. Transform assay to relative abundance
    GlobalPatterns <- transformAssay(GlobalPatterns, method = "relabundance")
    
    # 3. Plot abundance by taxonomic rank (Kingdom)
    p1 <- plotAbundance(GlobalPatterns, rank = "Kingdom", assay.type = "relabundance")
    ggsave("abundance_kingdom.pdf", plot = p1, width = 10, height = 7)
    
    # 4. Agglomerate and plot abundance
    GlobalPatterns_king <- agglomerateByRank(GlobalPatterns, "Kingdom")
    p2 <- plotAbundance(GlobalPatterns_king, assay.type = "relabundance")
    ggsave("abundance_king_agglomerated.pdf", plot = p2, width = 10, height = 7)
    
    # 5. Filter by prevalent taxa and plot
    prev_phylum <- getPrevalent(GlobalPatterns, rank = "Phylum", detection = 0.01)
    
    # Save the list of prevalent phyla to a CSV file
    write.csv(data.frame(Phylum = prev_phylum), "prevalent_phyla.csv", row.names = FALSE)
    
    p3 <- plotAbundance(
        GlobalPatterns[rowData(GlobalPatterns)\$Phylum %in% prev_phylum],
        rank = "Phylum",
        assay.type = "relabundance")
    ggsave("abundance_prevalent_phylum.pdf", plot = p3, width = 10, height = 7)
    
    # 6. Combine abundance plot with sample metadata using patchwork
    plots <- plotAbundance(
        GlobalPatterns[rowData(GlobalPatterns)\$Phylum %in% prev_phylum],
        features = "SampleType",
        rank = "Phylum",
        assay.type = "relabundance")
    
    p4 <- plots\$abundance / plots\$SampleType + plot_layout(heights = c(9, 1))
    ggsave("abundance_combined_patchwork.pdf", plot = p4, width = 12, height = 8)
    
    # Save the transformed TreeSummarizedExperiment object
    saveRDS(GlobalPatterns, "GlobalPatterns_transformed.rds")

    writeLines(c(
        '"BIOC_MIAVIZ_ABUNDANCE_PLOTTING":',
        paste0('    miaViz: ', as.character(packageVersion('miaViz')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_abundance_plotting.csv versions.yml
    """
}

workflow BIOC_MIAVIZ_ABUNDANCE_PLOTTING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ GlobalPatterns ] ]

    main:
    BIOC_MIAVIZ_ABUNDANCE_PLOTTING(ch_input)

    emit:
    tables   = BIOC_MIAVIZ_ABUNDANCE_PLOTTING.out.tables
    plots    = BIOC_MIAVIZ_ABUNDANCE_PLOTTING.out.plots
    objects  = BIOC_MIAVIZ_ABUNDANCE_PLOTTING.out.objects
    versions = BIOC_MIAVIZ_ABUNDANCE_PLOTTING.out.versions
}
