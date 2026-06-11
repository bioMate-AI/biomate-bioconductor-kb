#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: HiCBricks — import_from_mcool
// Create a Brick container and load contact matrices directly from an .mcool binary file.
// Input: H1-hESC-HiC-4DNFI7JNCNFB.mcool
// Container: quay.io/biocontainers/bioconductor-hicbricks:1.28.0--r45hdfd78af_0
// R packages: HiCBricks
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_HICBRICKS_IMPORT_FROM_MCOOL {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-hicbricks:1.28.0--r45hdfd78af_0"

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
    .bm_deps <- c("HiCBricks")
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
    
    # Load required library
    library(HiCBricks)
    
    # Define input file path (expected to be in the working directory)
    mcool_path <- "H1-hESC-HiC-4DNFI7JNCNFB.mcool"
    
    # Check if the input file exists
    if (!file.exists(mcool_path)) {
      stop(paste("Required input file not found in the working directory:", mcool_path))
    }
    
    # Define output directory
    out_dir <- "mcool_to_Brick_test_dir"
    if (!dir.exists(out_dir)) {
      dir.create(out_dir, recursive = TRUE)
    }
    
    # 1. Initialize the Brick objects directly from the mcool file metadata
    Create_many_Bricks_from_mcool(
      output_directory = out_dir, 
      file_prefix = "mcool_to_Brick_test", 
      mcool = mcool_path, 
      resolution = 10000, 
      experiment_name = "Testing mcool creation", 
      remove_existing = TRUE
    )
    
    # 2. Load the BrickContainer
    My_BrickContainer <- load_BrickContainer(project_dir = out_dir)
    
    # 3. Populate the Brick objects with normalized values from the mcool file
    Brick_load_data_from_mcool(
      Brick = My_BrickContainer, 
      mcool = mcool_path, 
      resolution = 10000, 
      cooler_read_limit = 10000000, 
      matrix_chunk = 2000, 
      remove_prior = TRUE, 
      norm_factor = "Iterative-Correction"
    )
    
    # Save the BrickContainer object as an RDS file
    saveRDS(My_BrickContainer, file = "My_BrickContainer.rds")
    
    # Extract and save the bintable for the loaded resolution to a CSV file
    bintable <- Brick_get_bintable(My_BrickContainer, resolution = 10000)
    bintable_df <- as.data.frame(bintable)
    write.csv(bintable_df, file = "bintable_resolution_10000.csv", row.names = FALSE)
    
    message("Pipeline completed successfully. Outputs saved to 'My_BrickContainer.rds' and 'bintable_resolution_10000.csv'.")

    writeLines(c(
        '"BIOC_HICBRICKS_IMPORT_FROM_MCOOL":',
        paste0('        HiCBricks: ', as.character(packageVersion("HiCBricks")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_import_from_mcool.csv versions.yml
    """
}

workflow BIOC_HICBRICKS_IMPORT_FROM_MCOOL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ H1-hESC-HiC-4DNFI7JNCNFB.mcool ] ]

    main:
    BIOC_HICBRICKS_IMPORT_FROM_MCOOL(ch_input)

    emit:
    tables   = BIOC_HICBRICKS_IMPORT_FROM_MCOOL.out.tables
    plots    = BIOC_HICBRICKS_IMPORT_FROM_MCOOL.out.plots
    objects  = BIOC_HICBRICKS_IMPORT_FROM_MCOOL.out.objects
    versions = BIOC_HICBRICKS_IMPORT_FROM_MCOOL.out.versions
}
