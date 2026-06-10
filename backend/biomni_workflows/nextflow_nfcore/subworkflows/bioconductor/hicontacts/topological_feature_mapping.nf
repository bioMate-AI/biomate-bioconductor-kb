#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: HiContacts — topological_feature_mapping
// Map chromosome compartments, compute diamond insulation scores, identify chromatin domain borders, and export results.
// Input: mcool_file.mcool
// Container: quay.io/biocontainers/bioconductor-hicontacts:1.12.0--r45hdfd78af_0
// R packages: HiCExperiment, HiContacts, IRanges, dplyr, ggplot2, rtracklayer
// Bioconductor: 3.20 | R: 4.4
// Requires: HiCExperiment, HiContacts, IRanges, dplyr, ggplot2, rtracklayer
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Import Hi-C matrix at a specific resolution. 2. Compute chromosome compartments using getCompartments(). 3. Export compartments as

nextflow.enable.dsl = 2

process BIOC_HICONTACTS_TOPOLOGICAL_FEATURE_MAPPING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20"

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
    .bm_deps <- c("HiCExperiment", "HiContacts", "IRanges", "dplyr", "ggplot2", "rtracklayer")
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
    library(dplyr)
    library(ggplot2)
    library(HiCExperiment)
    library(HiContacts)
    library(rtracklayer)
    
    # Define input file
    mcool_file <- "mcool_file.mcool"
    
    # 1. Import Hi-C matrix at a specific resolution
    # Check available resolutions in the mcool file to ensure robust loading
    temp_hic <- import(mcool_file, format = 'mcool')
    avail_res <- resolutions(temp_hic)
    initial_res <- 16000
    if (!initial_res %in% avail_res) {
        initial_res <- avail_res[which.min(abs(avail_res - 16000))]
    }
    
    hic <- import(mcool_file, format = 'mcool', resolution = initial_res)
    
    # 2. Compute chromosome compartments using getCompartments()
    # Dynamically select chromosomes to avoid errors if 'XV' and 'XVI' are not present
    available_chrs <- seqlevels(hic)
    target_chrs <- c('XV', 'XVI')
    if (!all(target_chrs %in% available_chrs)) {
        target_chrs <- head(available_chrs, min(2, length(available_chrs)))
    }
    
    hic <- getCompartments(hic, chromosomes = target_chrs)
    
    # 3. Export compartments as BigWig and BED files
    export(IRanges::coverage(metadata(hic)\$eigens, weight = 'eigen'), 'compartments.bw')
    export(
        topologicalFeatures(hic, 'compartments')[topologicalFeatures(hic, 'compartments')\$compartment == 'A'], 
        'A-compartments.bed'
    )
    export(
        topologicalFeatures(hic, 'compartments')[topologicalFeatures(hic, 'compartments')\$compartment == 'B'], 
        'B-compartments.bed'
    )
    
    # 4. Generate a saddle plot using plotSaddle()
    pdf('saddle_plot.pdf')
    print(plotSaddle(hic))
    dev.off()
    
    # 5. Compute diamond insulation scores using getDiamondInsulation()
    # 6. Identify domain borders using getBorders()
    # Dynamically adjust focus, resolution, and window size based on input file properties
    target_focus <- 'II:1-300000'
    if (!any(available_chrs == 'II')) {
        target_focus <- paste0(available_chrs[1], ":1-300000")
    }
    
    target_res <- 1000
    if (!target_res %in% avail_res) {
        target_res <- min(avail_res)
    }
    
    target_window <- 8000
    if (target_window < target_res) {
        target_window <- target_res * 8
    }
    
    hic <- refocus(hic, target_focus) |> 
        zoom(resolution = target_res) |> 
        getDiamondInsulation(window_size = target_window) |> 
        getBorders()
    
    # 7. Export insulation scores as BigWig and borders as BED
    export(IRanges::coverage(metadata(hic)\$insulation, weight = 'insulation'), 'insulation.bw')
    export(topologicalFeatures(hic, 'borders'), 'borders.bed')

    writeLines(c(
        '"BIOC_HICONTACTS_TOPOLOGICAL_FEATURE_MAPPING":',
        paste0('    HiContacts: ', as.character(packageVersion('HiContacts')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_topological_feature_mapping.csv versions.yml
    """
}

workflow BIOC_HICONTACTS_TOPOLOGICAL_FEATURE_MAPPING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ mcool_file.mcool ] ]

    main:
    BIOC_HICONTACTS_TOPOLOGICAL_FEATURE_MAPPING(ch_input)

    emit:
    tables   = BIOC_HICONTACTS_TOPOLOGICAL_FEATURE_MAPPING.out.tables
    plots    = BIOC_HICONTACTS_TOPOLOGICAL_FEATURE_MAPPING.out.plots
    objects  = BIOC_HICONTACTS_TOPOLOGICAL_FEATURE_MAPPING.out.objects
    versions = BIOC_HICONTACTS_TOPOLOGICAL_FEATURE_MAPPING.out.versions
}
