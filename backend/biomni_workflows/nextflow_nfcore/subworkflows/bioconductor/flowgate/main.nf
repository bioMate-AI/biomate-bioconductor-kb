#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: flowgate — interactive_manual_gating
// Import FCS files, convert to a GatingSet, apply compensation, interactively draw manual gates (polygon, span, quadrant), and export plots and statistics.
// Input: path_to_fcs, compmatrix
// Container: quay.io/biocontainers/bioconductor-flowgate:1.10.0--r45hdfd78af_0
// R packages: flowCore, flowGate, flowWorkspace, ggcyto, ggplot2, ncdfFlow
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: autoplot, density plot

nextflow.enable.dsl = 2

process BIOC_FLOWGATE_INTERACTIVE_MANUAL_GATING {
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
    .bm_deps <- c("flowCore", "flowGate", "flowWorkspace", "ggcyto", "ggplot2", "ncdfFlow")
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
    
    # Define paths to user input files in the working directory
    path_to_fcs <- "path_to_fcs"
    path_to_comp <- "compmatrix"
    
    # --- Read FCS files into a flowSet ---
    fs <- read.flowSet(path = path_to_fcs, pattern = ".FCS\$", full.names = TRUE)
    
    # --- Convert the flowSet to a GatingSet ---
    gs <- GatingSet(fs)
    
    # --- Read and apply compensation ---
    comp_matrix <- read.table(path_to_comp, header = TRUE, skip = 2, check.names = FALSE)
    comp <- compensation(comp_matrix)
    gs <- compensate(gs, comp)
    
    # Display channel and marker names
    print(colnames(gs))
    print(markernames(gs))
    
    # --- Interactively draw gates ---
    # Gate 1: Leukocytes (Polygon gate on FSC-H vs SSC-H)
    gs_gate_interactive(gs, filterId = "Leukocytes", dims = list("FSC-H", "SSC-H"))
    
    # Export Leukocytes plot
    pdf("plot_leukocytes_autoplot.pdf")
    print(autoplot(gs[[1]], gate = "Leukocytes"))
    dev.off()
    
    # Gate 2: CD45 (1-D span gate on CD45 histogram, subsetted on Leukocytes)
    gs_gate_interactive(gs, filterId = "CD45", dims = "CD45", subset = "Leukocytes")
    
    # Export CD45 plot
    pdf("plot_cd45_density.pdf")
    p_cd45 <- ggcyto(gs[[1]], aes("CD45")) + 
      geom_density() + 
      geom_gate("CD45") + 
      geom_stats()
    print(p_cd45)
    dev.off()
    
    # Gate 3: CD33 CD15 (Quadrant gate on CD33 vs CD15, subsetted on CD45)
    gs_gate_interactive(gs[[1]], filterId = "CD33 CD15", dims = list("CD33", "CD15"), subset = "CD45")
    
    # Get population paths
    pop_paths <- gs_get_pop_paths(gs)
    print(pop_paths)
    
    # Export CD33 vs CD15 quadrant plot
    pdf("plot_cd33_cd15_quadrant.pdf")
    p_quad <- ggcyto(gs[[1]], aes("CD33", "CD15")) + 
      geom_hex(bins = 128) + 
      scale_x_flowjo_biexp(maxValue = 252245, widthBasis = -29, pos = 4) + 
      scale_y_flowjo_biexp(maxValue = 250000, widthBasis = -12, pos = 5) + 
      geom_gate(c("CD33 APC-CD15 FITC+", 
                  "CD33 APC+CD15 FITC+", 
                  "CD33 APC+CD15 FITC-", 
                  "CD33 APC-CD15 FITC-")) + 
      geom_hline(yintercept = 80.2426) + 
      geom_vline(xintercept = 97.42192) + 
      geom_stats()
    print(p_quad)
    dev.off()
    
    # --- Save and reload the GatingSet ---
    save_gs(gs, "GvHD GatingSet.gs")
    gs <- load_gs(file.path("GvHD GatingSet.gs"))
    
    # --- Retrieve and export population statistics ---
    # Population counts
    counts <- gs_pop_get_count_fast(gs)
    write.csv(counts, "population_counts.csv", row.names = FALSE)
    
    # Percent statistics (all nodes)
    stats_percent <- gs_pop_get_stats(gs, type = "percent")
    write.csv(stats_percent, "stats_percent_all.csv", row.names = FALSE)
    
    # Percent statistics (CD45 node)
    stats_percent_cd45 <- gs_pop_get_stats(gs, type = "percent", nodes = "CD45")
    write.csv(stats_percent_cd45, "stats_percent_cd45.csv", row.names = FALSE)
    
    # Median Fluorescence Intensity (MFI) statistics
    stats_mfi <- gs_pop_get_stats(gs, type = pop.MFI)
    write.csv(stats_mfi, "stats_mfi.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_FLOWGATE_INTERACTIVE_MANUAL_GATING":',
        paste0('        flowgate: ', as.character(packageVersion("flowgate")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_interactive_manual_gating.csv versions.yml
    """
}

workflow BIOC_FLOWGATE_INTERACTIVE_MANUAL_GATING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ path_to_fcs, compmatrix ] ]

    main:
    BIOC_FLOWGATE_INTERACTIVE_MANUAL_GATING(ch_input)

    emit:
    tables   = BIOC_FLOWGATE_INTERACTIVE_MANUAL_GATING.out.tables
    plots    = BIOC_FLOWGATE_INTERACTIVE_MANUAL_GATING.out.plots
    objects  = BIOC_FLOWGATE_INTERACTIVE_MANUAL_GATING.out.objects
    versions = BIOC_FLOWGATE_INTERACTIVE_MANUAL_GATING.out.versions
}
