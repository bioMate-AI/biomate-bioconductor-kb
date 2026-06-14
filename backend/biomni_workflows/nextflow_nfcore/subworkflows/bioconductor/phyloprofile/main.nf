#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: phyloprofile — profile_processing_and_visualization
// Process raw orthology input data, generate a phylogenetic profile, and visualize it as a heatmap.
// Input: rawInput.txt
// Container: quay.io/biocontainers/bioconductor-phyloprofile:2.2.2--r45hdfd78af_0
// R packages: dplyr, ggplot2, PhyloProfile
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: heatmap, phylogenetic tree

nextflow.enable.dsl = 2

process BIOC_PHYLOPROFILE_PROFILE_PROCESSING_AND_VISUALIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-phyloprofile:2.2.2--r45hdfd78af_0"

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
    .bm_deps <- c("dplyr", "ggplot2", "PhyloProfile")
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
    library(PhyloProfile)
    library(ggplot2)
    
    # Define input file path
    rawInput <- "rawInput.txt"
    
    # Define parameters for profile processing
    rankName <- "class"
    refTaxon <- "Mammalia"
    taxaTree <- NULL
    sortedTaxonList <- NULL
    var1AggregateBy <- "max"
    var2AggregateBy <- "mean"
    percentCutoff <- c(0.0, 1.0)
    coorthologCutoffMax <- 10
    var1Cutoff <- c(0.75, 1.0)
    var2Cutoff <- c(0.5, 1.0)
    var1Relation <- "protein"
    var2Relation <- "species"
    groupByCat <- FALSE
    catDt <- NULL
    
    # Process the raw input file into a phylogenetic profile
    profileData <- fromInputToProfile(
        rawInput,
        rankName,
        refTaxon,
        taxaTree,
        sortedTaxonList,
        var1AggregateBy,
        var2AggregateBy,
        percentCutoff,
        coorthologCutoffMax,
        var1Cutoff,
        var2Cutoff,
        var1Relation,
        var2Relation,
        groupByCat,
        catDt
    )
    
    # Save the processed profile data
    write.csv(profileData, "processed_profile.csv", row.names = FALSE)
    saveRDS(profileData, "processed_profile.rds")
    
    # Prepare data for plotting using the processed profile
    plotDf <- dataMainPlot(profileData)
    
    # Define plot parameters
    plotParameter <- list(
        "xAxis" = "taxa",
        "var1ID" = "FAS_FW",
        "var2ID"  = "FAS_BW",
        "midVar1" = 0.5,
        "midColorVar1" =  "#FFFFFF",
        "lowColorVar1" =  "#FF8C00",
        "highColorVar1" = "#4682B4",
        "midVar2" = 1,
        "midColorVar2" =  "#FFFFFF",
        "lowColorVar2" = "#CB4C4E",
        "highColorVar2" = "#3E436F",
        "paraColor" = "#07D000",
        "xSize" = 8,
        "ySize" = 8,
        "legendSize" = 8,
        "mainLegend" = "top",
        "dotZoom" = 0,
        "xAngle" = 60,
        "guideline" = 0,
        "colorByGroup" = FALSE,
        "colorByOrthoID" = FALSE
    )
    
    # Generate the phylogenetic profile heatmap
    p <- heatmapPlotting(plotDf, plotParameter)
    
    # Save the generated plot
    ggsave("phyloprofile_heatmap.pdf", plot = p, width = 12, height = 10)
    saveRDS(p, "phyloprofile_plot.rds")

    writeLines(c(
        '"BIOC_PHYLOPROFILE_PROFILE_PROCESSING_AND_VISUALIZATION":',
        paste0('        phyloprofile: ', as.character(packageVersion("phyloprofile")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_profile_processing_and_visualization.csv versions.yml
    """
}

workflow BIOC_PHYLOPROFILE_PROFILE_PROCESSING_AND_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ rawInput.txt ] ]

    main:
    BIOC_PHYLOPROFILE_PROFILE_PROCESSING_AND_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_PHYLOPROFILE_PROFILE_PROCESSING_AND_VISUALIZATION.out.tables
    plots    = BIOC_PHYLOPROFILE_PROFILE_PROCESSING_AND_VISUALIZATION.out.plots
    objects  = BIOC_PHYLOPROFILE_PROFILE_PROCESSING_AND_VISUALIZATION.out.objects
    versions = BIOC_PHYLOPROFILE_PROFILE_PROCESSING_AND_VISUALIZATION.out.versions
}
