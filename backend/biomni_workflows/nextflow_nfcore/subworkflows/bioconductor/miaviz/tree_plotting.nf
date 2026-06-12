#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: miaViz — tree_plotting
// Visualize phylogenetic trees decorated with taxonomic, abundance, and prevalence metadata.
// Input: GlobalPatterns
// Container: quay.io/biocontainers/bioconductor-miaviz:1.18.0--r45hdfd78af_0
// R packages: ggplot2, mia, miaViz, scater
// Bioconductor: 3.20 | R: 4.4
// Requires: ggplot2, mia, miaViz, scater
// Visualizations: plot (ggplot/base)
// QC: cell QC metrics
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Agglomerate to Genus level
//  * 2. [Core Analysis] Calculate quality control metrics (mean, detection)
//  * 3. [Core Analysis] Filter to top 100 taxa
//  * 4. [Visualization & Output] Plot row tree with decorated tips (color, size)
//  * 5. [Visualization & Output] Plot tree with specific node/tip labels and rectangular layout
//  * 6. [Visualization & Output] Plot tree with colored edges

nextflow.enable.dsl = 2

process BIOC_MIAVIZ_TREE_PLOTTING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-metagenomics:3.20"

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
    .bm_deps <- c("ggplot2", "mia", "miaViz", "scater", "SummarizedExperiment")
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
    
    # Load required lib    library(SummarizedExperiment)
raries
    library(mia)
    library(miaViz)
    library(scater)
    library(ggplot2)
    
    # 1. Read the input TreeSummarizedExperiment object from the working directory
    input_file <- "GlobalPatterns"
    if (!file.exists(input_file)) {
        if (file.exists("GlobalPatterns.rds")) {
            input_file <- "GlobalPatterns.rds"
        } else {
            stop("Error: GlobalPatterns file not found in the working directory.")
        }
    }
    GlobalPatterns <- readRDS(input_file)
    
    # 2. Agglomerate to Genus level
    altExp(GlobalPatterns,"Genus") <- agglomerateByRank(GlobalPatterns,"Genus")
    
    # 3. Calculate quality control metrics (mean, detection)
    altExp(GlobalPatterns,"Genus") <- addPerFeatureQC(
        altExp(GlobalPatterns,"Genus"))
    rowData(altExp(GlobalPatterns,"Genus"))\$log_mean <- log(
        rowData(altExp(GlobalPatterns,"Genus"))\$mean)
    rowData(altExp(GlobalPatterns,"Genus"))\$detected <- rowData(
        altExp(GlobalPatterns,"Genus"))\$detected / 100
    
    # 4. Filter to top 100 taxa
    top_taxa <- getTop(
        altExp(GlobalPatterns,"Genus"),
        method="mean",
        top=100L,
        assay.type="counts")
    
    # 5. Plot row tree with decorated tips (color, size)
    p1 <- plotRowTree(
        altExp(GlobalPatterns,"Genus")[top_taxa,], tip.colour.by = "log_mean",
        tip.size.by = "detected")
    ggsave("plot1_decorated_tips.pdf", plot = p1, width = 10, height = 10)
    
    # 6. Plot tree with labels
    p2 <- plotRowTree(
        altExp(GlobalPatterns,"Genus")[top_taxa,],
        tip.colour.by = "log_mean", tip.size.by = "detected", show.label = TRUE)
    ggsave("plot2_with_labels.pdf", plot = p2, width = 12, height = 12)
    
    # 7. Plot tree with specific node/tip labels and rectangular layout
    labels <- c("Genus:Providencia", "Genus:Morganella", "0.961.60")
    p3 <- plotRowTree(
        altExp(GlobalPatterns,"Genus")[top_taxa,],
        tip.colour.by = "log_mean",
        tip.size.by = "detected",
        show.label = labels,
        layout="rectangular")
    ggsave("plot3_rectangular_layout.pdf", plot = p3, width = 10, height = 10)
    
    # 8. Plot tree with colored edges
    p4 <- plotRowTree(
        altExp(GlobalPatterns,"Genus")[top_taxa,],
        edge.colour.by = "Phylum",
        tip.colour.by = "log_mean")
    ggsave("plot4_colored_edges.pdf", plot = p4, width = 10, height = 10)
    
    # 9. Save meaningful outputs (CSV tables and processed RDS object)
    top_taxa_data <- as.data.frame(rowData(altExp(GlobalPatterns, "Genus")[top_taxa, ]))
    write.csv(top_taxa_data, "top_100_taxa_qc.csv", row.names = TRUE)
    
    saveRDS(GlobalPatterns, "GlobalPatterns_processed.rds")

    writeLines(c(
        '"BIOC_MIAVIZ_TREE_PLOTTING":',
        paste0('    miaViz: ', as.character(packageVersion('miaViz')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tree_plotting.csv versions.yml
    """
}

workflow BIOC_MIAVIZ_TREE_PLOTTING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ GlobalPatterns ] ]

    main:
    BIOC_MIAVIZ_TREE_PLOTTING(ch_input)

    emit:
    tables   = BIOC_MIAVIZ_TREE_PLOTTING.out.tables
    plots    = BIOC_MIAVIZ_TREE_PLOTTING.out.plots
    objects  = BIOC_MIAVIZ_TREE_PLOTTING.out.objects
    versions = BIOC_MIAVIZ_TREE_PLOTTING.out.versions
}
