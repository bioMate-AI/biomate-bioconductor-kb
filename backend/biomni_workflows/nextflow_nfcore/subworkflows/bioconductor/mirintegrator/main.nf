#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: mirIntegrator — augment_and_visualize_pathways
// Integrate miRNA-target interactions into signaling pathways and visualize the augmented pathways.
// Input: kegg_pathways, mirTarBase
// Container: quay.io/biocontainers/bioconductor-mirintegrator:1.40.0--r45hdfd78af_0
// R packages: graph, mirIntegrator, ROntoTools
// Bioconductor: 3.20 | R: 4.4
// Requires: graph, mirIntegrator
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load pathway and miRNA-target data
//  * 2. [Core Analysis] Integrate miRNAs into pathways using integrate_mir
//  * 3. [Visualization & Output] Plot a single augmented pathway using plot_augmented_pathway
//  * 4. [Visualization & Output] Plot overall pathway changes using plot_change
//  * 5. [Visualization & Output] Export augmented pathways to PDF using pathways2pdf

nextflow.enable.dsl = 2

process BIOC_MIRINTEGRATOR_AUGMENT_AND_VISUALIZE_PATHWAYS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    .bm_deps <- c("graph", "mirIntegrator", "ROntoTools")
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
        
        # mirIntegrator Pipeline: Augment and Visualize Pathways
        # This script integrates miRNA-target interactions into signaling pathways and visualizes the augmented pathways.
        
        # 1. Load Required Libraries
        library(mirIntegrator)
        library(graph)
        
        # 2. Load Pathway and miRNA-Target Data from User Input Files
        if (file.exists("kegg_pathways.rds")) {
          kegg_pathways <- readRDS("kegg_pathways.rds")
        } else if (file.exists("kegg_pathways.RData")) {
          env <- new.env()
          load("kegg_pathways.RData", envir = env)
          kegg_pathways <- env[[names(env)[1]]]
        } else {
          stop("Error: kegg_pathways file (RDS or RData) not found in the working directory.")
        }
        
        if (file.exists("mirTarBase.rds")) {
          mirTarBase <- readRDS("mirTarBase.rds")
        } else if (file.exists("mirTarBase.csv")) {
          mirTarBase <- read.csv("mirTarBase.csv", stringsAsFactors = FALSE)
        } else if (file.exists("mirTarBase.RData")) {
          env <- new.env()
          load("mirTarBase.RData", envir = env)
          mirTarBase <- env[[names(env)[1]]]
        } else {
          stop("Error: mirTarBase file (RDS, CSV, or RData) not found in the working directory.")
        }
        
        # Construct names_pathways dynamically from the pathway names
        names_pathways <- names(kegg_pathways)
        names(names_pathways) <- names(kegg_pathways)
        
        # Dynamically select an available pathway from the user's input
        target_pathway_id <- names(kegg_pathways)[1]
        
        # Keep full copies of the datasets to restore them later for full-scale plotting
        kegg_pathways_full <- kegg_pathways
        names_pathways_full <- names_pathways
        
        # 3. Integrate miRNAs into Pathways using integrate_mir
        kegg_pathways <- head(kegg_pathways, 3) # Subset to a few pathways for demonstration
        augmented_pathways <- integrate_mir(kegg_pathways, mirTarBase)
        head(augmented_pathways)
        augmented_pathways[[target_pathway_id]]
        
        # 4. Plot a Single Augmented Pathway using plot_augmented_pathway
        pdf("augmented_pathway_plot.pdf", width = 10, height = 8)
        plot_augmented_pathway(kegg_pathways[[target_pathway_id]], 
                               augmented_pathways[[target_pathway_id]],
                               names_pathways[target_pathway_id] )
        dev.off()
        
        # 5. Plot Overall Pathway Changes using plot_change
        # Restore full datasets to match the vignette's state before plot_change
        kegg_pathways <- kegg_pathways_full
        names_pathways <- names_pathways_full
        augmented_pathways <- integrate_mir(kegg_pathways, mirTarBase)
        
        pdf("plot_change.pdf", width = 10, height = 6)
        print(plot_change(kegg_pathways, augmented_pathways, names_pathways))
        dev.off()
        
        pdf("plot_change_size10.pdf", width = 10, height = 6)
        print(plot_change(kegg_pathways, augmented_pathways, names_pathways, sizeT = 10))
        dev.off()
        
        # 6. Export Augmented Pathways to PDF using pathways2pdf
        pathways2pdf(head(kegg_pathways, 3), head(augmented_pathways, 3),
                     head(names_pathways, 3), "three_pathways.pdf")
        
        # 7. Save Meaningful Results to Disk
        saveRDS(augmented_pathways, "augmented_pathways.rds")

    writeLines(c(
        '"BIOC_MIRINTEGRATOR_AUGMENT_AND_VISUALIZE_PATHWAYS":',
        paste0('    mirIntegrator: ', as.character(packageVersion('mirIntegrator')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_augment_and_visualize_pathways.csv versions.yml
    """
}

workflow BIOC_MIRINTEGRATOR_AUGMENT_AND_VISUALIZE_PATHWAYS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ kegg_pathways, mirTarBase ] ]

    main:
    BIOC_MIRINTEGRATOR_AUGMENT_AND_VISUALIZE_PATHWAYS(ch_input)

    emit:
    tables   = BIOC_MIRINTEGRATOR_AUGMENT_AND_VISUALIZE_PATHWAYS.out.tables
    plots    = BIOC_MIRINTEGRATOR_AUGMENT_AND_VISUALIZE_PATHWAYS.out.plots
    objects  = BIOC_MIRINTEGRATOR_AUGMENT_AND_VISUALIZE_PATHWAYS.out.objects
    versions = BIOC_MIRINTEGRATOR_AUGMENT_AND_VISUALIZE_PATHWAYS.out.versions
}
