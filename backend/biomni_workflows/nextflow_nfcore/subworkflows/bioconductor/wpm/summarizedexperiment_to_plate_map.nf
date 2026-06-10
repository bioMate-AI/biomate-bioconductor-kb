#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: wpm — summarizedexperiment_to_plate_map
// Generate and visualize a randomized well-plate map starting from a SummarizedExperiment object.
// Input: se
// Container: quay.io/biocontainers/bioconductor-wpm:1.20.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_WPM_SUMMARIZEDEXPERIMENT_TO_PLATE_MAP {
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
    .bm_deps <- c("SummarizedExperiment", "ggplot2", "wpm")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(SummarizedExperiment)
    library(wpm)
    library(ggplot2)
    
    # Read the input SummarizedExperiment object from the working directory
    se_path <- "se"
    if (!file.exists(se_path) && file.exists("se.rds")) {
      se_path <- "se.rds"
    }
    if (!file.exists(se_path)) {
      stop("Error: Input file 'se' or 'se.rds' not found in the working directory.")
    }
    
    se <- readRDS(se_path)
    
    # Extract colData to ensure it is available as a data frame for visualization parameters
    colData <- as.data.frame(SummarizedExperiment::colData(se))
    
    # 1. Convert the SummarizedExperiment object into the WPM-compatible dataframe format
    df <- wpm::convertSE(se, "Treatment")
    
    # 2. Run the randomization algorithm using wrapperWPM
    wpm_result <- wpm::wrapperWPM(user_df = df,
                plate_dims = list(8,12),
                nb_plates = 1,
                forbidden_wells = "A1,A2,A3",
                fixed_wells = "B1,B2",
                spatial_constraint = "NS")
    
    # 3. Visualize the generated plate map using drawMap
    drawned_map <- wpm::drawMap(df = wpm_result,
            sample_gps = length(levels(as.factor(colData\$Treatment))),
            gp_levels = gp_lvl <- levels(as.factor(colData\$Treatment)),
            plate_lines = 8,
            plate_cols = 12,
            project_title = "my Project Title")
    
    # Write outputs to the working directory
    write.csv(wpm_result, "wpm_result.csv", row.names = FALSE)
    saveRDS(wpm_result, "wpm_result.rds")
    
    ggplot2::ggsave(
        filename = "plate_map.pdf",
        plot = drawned_map,
        width = 10,
        height = 7,
        units = "in"
    )

    cat <<-END_VERSIONS > versions.yml
    "BIOC_WPM_SUMMARIZEDEXPERIMENT_TO_PLATE_MAP":
        wpm: \$(Rscript -e 'cat(as.character(packageVersion("wpm")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_summarizedexperiment_to_plate_map.csv versions.yml
    """
}

workflow BIOC_WPM_SUMMARIZEDEXPERIMENT_TO_PLATE_MAP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ se ] ]

    main:
    BIOC_WPM_SUMMARIZEDEXPERIMENT_TO_PLATE_MAP(ch_input)

    emit:
    tables   = BIOC_WPM_SUMMARIZEDEXPERIMENT_TO_PLATE_MAP.out.tables
    plots    = BIOC_WPM_SUMMARIZEDEXPERIMENT_TO_PLATE_MAP.out.plots
    objects  = BIOC_WPM_SUMMARIZEDEXPERIMENT_TO_PLATE_MAP.out.objects
    versions = BIOC_WPM_SUMMARIZEDEXPERIMENT_TO_PLATE_MAP.out.versions
}
