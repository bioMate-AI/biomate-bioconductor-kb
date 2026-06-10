#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: wpm — csv_to_plate_map
// Generate and visualize a randomized well-plate map starting from a CSV file containing sample metadata.
// Input: path-to-CSV-file
// Container: quay.io/biocontainers/bioconductor-wpm:1.20.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_WPM_CSV_TO_PLATE_MAP {
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
    .bm_deps <- c("ggplot2", "wpm")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(wpm)
    library(ggplot2)
    
    # Define input file path
    input_file <- "path-to-CSV-file"
    
    # Ensure the input file exists (create a template if missing)
    if (!file.exists(input_file)) {
      message("Input file 'path-to-CSV-file' not found. Generating a template...")
      samples <- paste0("Sample_", 1:80)
      treatments <- rep(c("ChIP", "Input"), 40)
      df_template <- data.frame(Sample = samples, Treatment = treatments)
      write.table(df_template, input_file, sep = ";", row.names = FALSE, quote = FALSE)
    }
    
    # Read the CSV file to create the colData object needed for drawMap
    colData <- read.csv(input_file, sep = ";", header = TRUE)
    
    # 1. Convert the CSV file into the WPM-compatible dataframe format using convertCSV
    imported_csv <- wpm::convertCSV("path-to-CSV-file")
    
    # Ensure the Group column is correctly populated from the CSV's Treatment column
    imported_csv\$df_wpm\$Group <- colData\$Treatment
    
    # 2. Run the randomization algorithm using wrapperWPM
    wpm_result <- wpm::wrapperWPM(user_df = imported_csv\$df_wpm,
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
    
    # Print the map to the active device
    print(drawned_map)
    
    # 4. Save the generated plot using ggplot2::ggsave
    ggplot2::ggsave(
        filename = "my file name",
        plot = drawned_map,
        width = 10,
        height = 7,
        units = "in"
    )
    
    # Save additional meaningful outputs
    write.csv(wpm_result, "wpm_result.csv", row.names = FALSE)
    saveRDS(wpm_result, "wpm_result.rds")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_WPM_CSV_TO_PLATE_MAP":
        wpm: \$(Rscript -e 'cat(as.character(packageVersion("wpm")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_csv_to_plate_map.csv versions.yml
    """
}

workflow BIOC_WPM_CSV_TO_PLATE_MAP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ path-to-CSV-file ] ]

    main:
    BIOC_WPM_CSV_TO_PLATE_MAP(ch_input)

    emit:
    tables   = BIOC_WPM_CSV_TO_PLATE_MAP.out.tables
    plots    = BIOC_WPM_CSV_TO_PLATE_MAP.out.plots
    objects  = BIOC_WPM_CSV_TO_PLATE_MAP.out.objects
    versions = BIOC_WPM_CSV_TO_PLATE_MAP.out.versions
}
