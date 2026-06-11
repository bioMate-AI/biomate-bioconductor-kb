#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: cfdnakit — create_panel_of_normals
// Create a Panel of Normals (PoN) profile from a list of healthy control SampleFragment RDS files.
// Input: Pon-list.txt
// Container: quay.io/biocontainers/bioconductor-cfdnakit:1.8.0--r45hdfd78af_0
// R packages: cfdnakit
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CFDNAKIT_CREATE_PANEL_OF_NORMALS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-cfdnakit:1.8.0--r45hdfd78af_0"

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
    .bm_deps <- c("cfdnakit")
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
    
    # Load the required library
    library(cfdnakit)
    
    # Define the user input file
    input_file <- "Pon-list.txt"
    
    # Validate the presence of the input file
    if (!file.exists(input_file)) {
      stop(paste("Error: Required input file '", input_file, "' not found in the working directory.", sep = ""))
    }
    
    # Verify that the paths listed inside the file exist
    sample_paths <- readLines(input_file, warn = FALSE)
    sample_paths <- sample_paths[sample_paths != ""] # Remove empty lines
    missing_files <- sample_paths[!file.exists(sample_paths)]
    
    if (length(missing_files) > 0) {
      stop(paste("Error: The following SampleFragment RDS files listed in '", input_file, "' do not exist:\n", 
                 paste(missing_files, collapse = "\n"), sep = ""))
    }
    
    # Stage 1: Generate PoN profile using create_PoN
    # Documented call: PoN.profiles <- create_PoN("Path.to/Pon-list.txt")
    PoN.profiles <- create_PoN(input_file)
    
    # Stage 2: Save the PoN profile to an RDS file
    # Documented call: saveRDS(PoN.profiles, "PoN.rds")
    saveRDS(PoN.profiles, "PoN.rds")
    
    cat("Workflow complete. Panel of Normals profile saved to 'PoN.rds'.\n")

    writeLines(c(
        '"BIOC_CFDNAKIT_CREATE_PANEL_OF_NORMALS":',
        paste0('        cfdnakit: ', as.character(packageVersion("cfdnakit")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_create_panel_of_normals.csv versions.yml
    """
}

workflow BIOC_CFDNAKIT_CREATE_PANEL_OF_NORMALS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Pon-list.txt ] ]

    main:
    BIOC_CFDNAKIT_CREATE_PANEL_OF_NORMALS(ch_input)

    emit:
    tables   = BIOC_CFDNAKIT_CREATE_PANEL_OF_NORMALS.out.tables
    plots    = BIOC_CFDNAKIT_CREATE_PANEL_OF_NORMALS.out.plots
    objects  = BIOC_CFDNAKIT_CREATE_PANEL_OF_NORMALS.out.objects
    versions = BIOC_CFDNAKIT_CREATE_PANEL_OF_NORMALS.out.versions
}
