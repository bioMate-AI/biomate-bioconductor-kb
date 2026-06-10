#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: wpm — eset_msnset_to_plate_map
// Generate and visualize a randomized well-plate map starting from an ExpressionSet or MSnSet object.
// Input: my_MSnSet_object
// Container: quay.io/biocontainers/bioconductor-wpm:1.20.0--r45hdfd78af_0
// Requires: Biobase, ggplot2, wpm
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Convert the ExpressionSet/MSnSet object into the WPM-compatible format using convertESet
//  * 2. [Core Analysis] Run the backtracking randomization algorithm using wrapperWPM
//  * 3. [Visualization & Output] Visualize the generated plate map using drawMap

nextflow.enable.dsl = 2

process BIOC_WPM_ESET_MSNSET_TO_PLATE_MAP {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20"

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
    .bm_deps <- c("Biobase", "ggplot2", "wpm")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
    
    # Load required libraries
    library(wpm)
    library(Biobase)
    library(ggplot2)
    
    # -----------------------------------------------------------------------------
    # Stage 0: Read User Input
    # -----------------------------------------------------------------------------
    # The pipeline expects 'my_MSnSet_object' (an ExpressionSet or MSnSet object)
    # in the working directory, saved as an RDS file.
    input_file <- "my_MSnSet_object"
    if (!file.exists(input_file) && file.exists("my_MSnSet_object.rds")) {
      input_file <- "my_MSnSet_object.rds"
    }
    
    if (!file.exists(input_file)) {
      stop("Error: Required input file 'my_MSnSet_object' or 'my_MSnSet_object.rds' not found in the working directory.")
    }
    
    # Read the ExpressionSet / MSnSet object
    my_MSnSet_object <- readRDS(input_file)
    
    # Extract phenoData for downstream visualization parameters
    pd <- Biobase::pData(my_MSnSet_object)
    
    # Dynamically determine the grouping column (using the first column of phenoData)
    group_col <- colnames(pd)[1]
    
    # -----------------------------------------------------------------------------
    # Stage 1: Convert the ExpressionSet/MSnSet object into WPM-compatible format
    # -----------------------------------------------------------------------------
    df <- wpm::convertESet(my_MSnSet_object, group_col)
    
    # -----------------------------------------------------------------------------
    # Stage 2: Run the backtracking randomization algorithm using wrapperWPM
    # -----------------------------------------------------------------------------
    wpm_result <- wpm::wrapperWPM(user_df = df,
                plate_dims = list(8,12),
                nb_plates = 1,
                forbidden_wells = "A1,A2,A3",
                fixed_wells = "B1,B2",
                spatial_constraint = "NS")
    
    # -----------------------------------------------------------------------------
    # Stage 3: Visualize the generated plate map using drawMap
    # -----------------------------------------------------------------------------
    drawned_map <- wpm::drawMap(df = wpm_result,
            sample_gps = length(levels(as.factor(pd[[group_col]]))),
            gp_levels = gp_lvl <- levels(as.factor(pd[[group_col]])),
            plate_lines = 8,
            plate_cols = 12,
            project_title = "my Project Title")
    
    # -----------------------------------------------------------------------------
    # Stage 4: Write Outputs
    # -----------------------------------------------------------------------------
    # Save the randomized plate map dataframe as CSV
    write.csv(wpm_result, "wpm_plate_map_layout.csv", row.names = FALSE)
    
    # Save the complete result as an RDS object
    saveRDS(wpm_result, "wpm_result.rds")
    
    # Save the generated plate map visualization as a PDF
    ggplot2::ggsave(
        filename = "wpm_plate_map_plot.pdf",
        plot = drawned_map,
        width = 10,
        height = 7,
        units = "in"
    )

    writeLines(c(
        '"BIOC_WPM_ESET_MSNSET_TO_PLATE_MAP":',
        paste0('    wpm: ', as.character(packageVersion('wpm')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_eset_msnset_to_plate_map.csv versions.yml
    """
}

workflow BIOC_WPM_ESET_MSNSET_TO_PLATE_MAP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ my_MSnSet_object ] ]

    main:
    BIOC_WPM_ESET_MSNSET_TO_PLATE_MAP(ch_input)

    emit:
    tables   = BIOC_WPM_ESET_MSNSET_TO_PLATE_MAP.out.tables
    plots    = BIOC_WPM_ESET_MSNSET_TO_PLATE_MAP.out.plots
    objects  = BIOC_WPM_ESET_MSNSET_TO_PLATE_MAP.out.objects
    versions = BIOC_WPM_ESET_MSNSET_TO_PLATE_MAP.out.versions
}
