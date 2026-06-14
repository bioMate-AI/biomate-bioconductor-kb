#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: wpm — expressionset_to_plate_map
// Generate and visualize a randomized well-plate map starting from an ExpressionSet or MSnSet object.
// Input: my_MSnSet_object
// Container: quay.io/biocontainers/bioconductor-wpm:1.20.0--r45hdfd78af_0
// R packages: Biobase, ggplot2, wpm
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: plot (ggplot/base)

nextflow.enable.dsl = 2

process BIOC_WPM_EXPRESSIONSET_TO_PLATE_MAP {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-wpm:1.20.0--r45hdfd78af_0"

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
    library(wpm)
    library(Biobase)
    library(ggplot2)
    
    # --- Read the user input file ---
    # The user input is 'my_MSnSet_object' in the working directory.
    if (file.exists("my_MSnSet_object")) {
      my_MSnSet_object <- readRDS("my_MSnSet_object")
    } else if (file.exists("my_MSnSet_object.rds")) {
      my_MSnSet_object <- readRDS("my_MSnSet_object.rds")
    } else {
      stop("Error: Input file 'my_MSnSet_object' not found in the working directory.")
    }
    
    # Extract phenoData to get the grouping factor levels
    pd <- Biobase::pData(my_MSnSet_object)
    
    # --- Convert the ExpressionSet/MSnSet object into the ---
    df <- wpm::convertESet(my_MSnSet_object, "Environment")
    
    # --- Run the randomization algorithm using wrapperWPM ---
    wpm_result <- wpm::wrapperWPM(user_df = df,
                plate_dims = list(8,12),
                nb_plates = 1,
                forbidden_wells = "A1,A2,A3",
                fixed_wells = "B1,B2",
                spatial_constraint = "NS")
    
    # --- Visualize the generated plate map using drawMap ---
    numberOfThePlate <- 1
    drawned_map <- wpm::drawMap(df = wpm_result[[numberOfThePlate]],
            sample_gps = length(levels(as.factor(pd\$Environment))),
            gp_levels = gp_lvl <- levels(as.factor(pd\$Environment)),
            plate_lines = 8,
            plate_cols = 12,
            project_title = "my Project Title")
    
    # Print the map to the standard output/device
    print(drawned_map)
    
    # --- Save outputs to the working directory ---
    # Save the full WPM result list as an RDS object
    saveRDS(wpm_result, "wpm_result.rds")
    
    # Save the layout dataframe for the plate as a CSV file
    write.csv(wpm_result[[numberOfThePlate]], "plate_map_layout.csv", row.names = FALSE)
    
    # Save the visualization plot as a PDF
    ggplot2::ggsave(
        filename = "plate_map.pdf",
        plot = drawned_map,
        width = 10,
        height = 7,
        units = "in"
    )

    writeLines(c(
        '"BIOC_WPM_EXPRESSIONSET_TO_PLATE_MAP":',
        paste0('        wpm: ', as.character(packageVersion("wpm")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_expressionset_to_plate_map.csv versions.yml
    """
}

workflow BIOC_WPM_EXPRESSIONSET_TO_PLATE_MAP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ my_MSnSet_object ] ]

    main:
    BIOC_WPM_EXPRESSIONSET_TO_PLATE_MAP(ch_input)

    emit:
    tables   = BIOC_WPM_EXPRESSIONSET_TO_PLATE_MAP.out.tables
    plots    = BIOC_WPM_EXPRESSIONSET_TO_PLATE_MAP.out.plots
    objects  = BIOC_WPM_EXPRESSIONSET_TO_PLATE_MAP.out.objects
    versions = BIOC_WPM_EXPRESSIONSET_TO_PLATE_MAP.out.versions
}
