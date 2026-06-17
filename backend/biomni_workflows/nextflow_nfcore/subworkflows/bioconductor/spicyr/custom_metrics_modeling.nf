#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: spicyR — custom_metrics_modeling
// Perform spatial modeling using custom distance or abundance metrics, such as kNN interaction graphs, instead of the default L-function.
// Input: kerenSPE
// Container: quay.io/biocontainers/bioconductor-spicyr:1.22.0--r45hdfd78af_0
// R packages: SpatialExperiment, SummarizedExperiment, dplyr, ggplot2, imcRtools, spicyR
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SPICYR_CUSTOM_METRICS_MODELING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-spicyr:1.22.0--r45hdfd78af_0"

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
    .bm_deps <- c("SpatialExperiment", "SummarizedExperiment", "dplyr", "ggplot2", "imcRtools", "spicyR")
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
    library(SummarizedExperiment)
    
    # Workaround for S4 method dispatch bug in spicyR
    methods::setClassUnion("ExpData", c("matrix", "dgCMatrix", "ExpressionSet", "SummarizedExperiment"))
    
    library(spicyR)
    library(ggplot2)
    library(SpatialExperiment)
    library(imcRtools)
    library(dplyr)
    
    # Read the input file from the working directory
    if (file.exists("kerenSPE")) {
      kerenSPE <- readRDS("kerenSPE")
    } else if (file.exists("kerenSPE.rds")) {
      kerenSPE <- readRDS("kerenSPE.rds")
    } else {
      stop("Error: kerenSPE file not found in the working directory.")
    }
    
    # --- Build a spatial graph using imcRtools::buildSpatialGraph() ---
    kerenSPE <- imcRtools::buildSpatialGraph(kerenSPE, 
                                             img_id = "imageID", 
                                             type = "knn", k = 20,
                                            coords = c("x", "y"))
    
    # --- Convert the spatial graph into an abundance matrix using ---
    pairAbundances <- convPairs(kerenSPE,
                      colPair = "knn_interaction_graph")
    
    # Save pair abundances to CSV
    write.csv(as.data.frame(pairAbundances), "pair_abundances.csv", row.names = TRUE)
    
    # Print head of B_cell__B_cell as shown in the vignette
    print(head(pairAbundances["B_cell__B_cell"]))
    
    # --- Run spicy() with the custom abundance matrix passed to ---
    spicyTestColPairs <- spicy(
      kerenSPE,
      condition = "tumour_type",
      alternateResult = pairAbundances,
      weights = FALSE
    )
    
    # Save the spicy results object
    saveRDS(spicyTestColPairs, "spicyTestColPairs.rds")
    
    # --- Retrieve top pairs using topPairs() and save to CSV ---
    top_pairs_df <- topPairs(spicyTestColPairs)
    write.csv(top_pairs_df, "top_pairs_colpairs.csv", row.names = TRUE)
    print(head(top_pairs_df))
    
    # --- Visualize results using signifPlot() and save to PDF ---
    pdf("signif_plot_colpairs.pdf", width = 8, height = 8)
    signifPlot(
      spicyTestColPairs,
      breaks = c(-3, 3, 1),
      marksToPlot = c("Macrophages", "dn_T_CD3", "CD4_T_cell", 
                      "B_cell", "DC_or_Mono", "Neutrophils", "CD8_T_cell")
    )
    dev.off()

    writeLines(c(
        '"BIOC_SPICYR_CUSTOM_METRICS_MODELING":',
        paste0('        spicyR: ', as.character(packageVersion("spicyR")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_custom_metrics_modeling.csv versions.yml
    """
}

workflow BIOC_SPICYR_CUSTOM_METRICS_MODELING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ kerenSPE ] ]

    main:
    BIOC_SPICYR_CUSTOM_METRICS_MODELING(ch_input)

    emit:
    tables   = BIOC_SPICYR_CUSTOM_METRICS_MODELING.out.tables
    plots    = BIOC_SPICYR_CUSTOM_METRICS_MODELING.out.plots
    objects  = BIOC_SPICYR_CUSTOM_METRICS_MODELING.out.objects
    versions = BIOC_SPICYR_CUSTOM_METRICS_MODELING.out.versions
}
