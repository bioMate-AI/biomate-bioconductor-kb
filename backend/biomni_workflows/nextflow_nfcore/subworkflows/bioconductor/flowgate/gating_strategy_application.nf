#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: flowgate — gating_strategy_application
// Define a multi-gate gating strategy in a tibble and apply it sequentially to a GatingSet using batch interactive gating.
// Input: path_to_fcs, compmatrix
// Container: quay.io/biocontainers/bioconductor-flowgate:1.10.0--r45hdfd78af_0
// R packages: flowCore, flowGate, flowWorkspace, ggcyto, ggplot2
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FLOWGATE_GATING_STRATEGY_APPLICATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-flowgate:1.10.0--r45hdfd78af_0"

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
    .bm_deps <- c("flowCore", "flowGate", "flowWorkspace", "ggcyto", "ggplot2")
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
    library(flowGate)
    library(flowCore)
    library(flowWorkspace)
    library(ggcyto)
    library(ggplot2)
    
    # 1. Import FCS files and create a compensated GatingSet
    # Read from the user-specified directory 'path_to_fcs'
    path_to_fcs <- "path_to_fcs"
    fs <- read.flowSet(path = path_to_fcs, pattern = ".FCS\$", full.names = TRUE)
    gs <- GatingSet(fs)
    
    # Read the user-specified compensation matrix file 'compmatrix'
    path_to_comp <- "compmatrix"
    comp_matrix <- read.table(path_to_comp, header = TRUE, skip = 2, check.names = FALSE)
    comp <- compensation(comp_matrix)
    gs <- compensate(gs, comp)
    
    # 2. Define a gating strategy tibble
    strategy <- tibble::tribble(
      ~ filterId, ~ dims, ~ subset, ~ bins,
      "Leukocytes" , list ( "FSC-H" , "SSC-H" ), "root" , 256 ,
      "CD45" , list ( "CD45" ), "Leukocytes" , 256 ,
      "CD33 CD15" , list ( "CD33" , "CD15" ), "CD45" , 64
    )
    
    # 3. Apply the gating strategy sequentially
    # Note: This function launches an interactive Shiny gadget for gating.
    gs_apply_gating_strategy(gs, gating_strategy = strategy)
    
    # 4. Save meaningful results and outputs
    # Save the GatingSet object
    save_gs(gs, "gated_GatingSet.gs")
    
    # Retrieve and save summary statistics
    tryCatch({
      stats_percent <- gs_pop_get_stats(gs, type = "percent")
      write.csv(stats_percent, "gating_stats_percent.csv", row.names = FALSE)
    }, error = function(e) {
      message("Could not retrieve percent stats: ", e\$message)
    })
    
    tryCatch({
      stats_count <- gs_pop_get_count_fast(gs)
      write.csv(stats_count, "gating_stats_counts.csv", row.names = FALSE)
    }, error = function(e) {
      message("Could not retrieve count stats: ", e\$message)
    })
    
    # Generate and save diagnostic plots
    pdf("gating_strategy_plots.pdf", width = 11, height = 8.5)
    tryCatch({
      # Plot Leukocytes gate for the first sample
      p1 <- autoplot(gs[[1]], gate = "Leukocytes")
      print(p1)
    }, error = function(e) {
      message("Could not plot Leukocytes gate: ", e\$message)
    })
    
    tryCatch({
      # Plot CD45 gate for the first sample
      p2 <- ggcyto(gs[[1]], aes("CD45")) +
        geom_density() +
        geom_gate("CD45") +
        geom_stats()
      print(p2)
    }, error = function(e) {
      message("Could not plot CD45 gate: ", e\$message)
    })
    dev.off()

    writeLines(c(
        '"BIOC_FLOWGATE_GATING_STRATEGY_APPLICATION":',
        paste0('        flowgate: ', as.character(packageVersion("flowgate")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gating_strategy_application.csv versions.yml
    """
}

workflow BIOC_FLOWGATE_GATING_STRATEGY_APPLICATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ path_to_fcs, compmatrix ] ]

    main:
    BIOC_FLOWGATE_GATING_STRATEGY_APPLICATION(ch_input)

    emit:
    tables   = BIOC_FLOWGATE_GATING_STRATEGY_APPLICATION.out.tables
    plots    = BIOC_FLOWGATE_GATING_STRATEGY_APPLICATION.out.plots
    objects  = BIOC_FLOWGATE_GATING_STRATEGY_APPLICATION.out.objects
    versions = BIOC_FLOWGATE_GATING_STRATEGY_APPLICATION.out.versions
}
