#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: mungesumstats — import_open_gwas
// Search for and import standardised GWAS summary statistics directly from the MRC IEU Open GWAS Project.
// Input: OPENGWAS_JWT
// Container: quay.io/biocontainers/bioconductor-mungesumstats:1.18.1--r45hdfd78af_0
// R packages: MungeSumstats, dplyr
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MUNGESUMSTATS_IMPORT_OPEN_GWAS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-mungesumstats:1.18.1--r45hdfd78af_0"

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
    .bm_deps <- c("MungeSumstats", "dplyr")
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
    library(MungeSumstats)
    library(dplyr)
    
    # ------------------------------------------------------------------------------
    # 1. Read User Input (API Token) and Authenticate
    # ------------------------------------------------------------------------------
    token_file <- "OPENGWAS_JWT"
    if (file.exists(token_file)) {
      token <- trimws(readLines(token_file, warn = FALSE)[1])
      Sys.setenv(OPENGWAS_JWT = token)
      message("Successfully loaded OPENGWAS_JWT and set environment variable.")
    } else {
      stop("Required input file 'OPENGWAS_JWT' containing the API token was not found in the working directory.")
    }
    
    # ------------------------------------------------------------------------------
    # 2. Execute Documented Workflow
    # ------------------------------------------------------------------------------
    
    # Stage 1: Search for datasets of interest using find_sumstats() with trait and sample size filters
    message("Searching for GWAS datasets...")
    metagwas <- MungeSumstats::find_sumstats(traits = c("parkinson","alzheimer"), min_sample_size = 1000)
    
    # Sort and extract IDs
    ids <- (dplyr::arrange(metagwas, nsnp))\$id
    
    # Stage 2: Import and format the selected datasets using import_sumstats()
    message("Importing and standardising selected GWAS summary statistics...")
    datasets <- MungeSumstats::import_sumstats(ids = "ieu-a-298", ref_genome = "GRCH37")
    
    # ------------------------------------------------------------------------------
    # 3. Save Outputs to Working Directory
    # ------------------------------------------------------------------------------
    
    # Save the search metadata
    write.csv(metagwas, "metagwas_search_results.csv", row.names = FALSE)
    writeLines(ids, "sorted_ids.txt")
    
    # Copy the imported datasets from temp directory to the working directory to preserve them
    preserved_datasets <- list()
    for (id in names(datasets)) {
      temp_path <- datasets[[id]]
      dest_path <- paste0(id, ".tsv.gz")
      if (file.exists(temp_path)) {
        file.copy(temp_path, dest_path, overwrite = TRUE)
        preserved_datasets[[id]] <- dest_path
        message(paste("Saved formatted dataset for", id, "to", dest_path))
      }
    }
    
    # Save the mapping of dataset IDs to their local preserved paths
    results_df <- data.frame(
      id = names(preserved_datasets),
      path = unlist(preserved_datasets),
      stringsAsFactors = FALSE
    )
    write.csv(results_df, "imported_datasets_mapping.csv", row.names = FALSE)
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_MUNGESUMSTATS_IMPORT_OPEN_GWAS":',
        paste0('        mungesumstats: ', as.character(packageVersion("mungesumstats")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_import_open_gwas.csv versions.yml
    """
}

workflow BIOC_MUNGESUMSTATS_IMPORT_OPEN_GWAS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ OPENGWAS_JWT ] ]

    main:
    BIOC_MUNGESUMSTATS_IMPORT_OPEN_GWAS(ch_input)

    emit:
    tables   = BIOC_MUNGESUMSTATS_IMPORT_OPEN_GWAS.out.tables
    plots    = BIOC_MUNGESUMSTATS_IMPORT_OPEN_GWAS.out.plots
    objects  = BIOC_MUNGESUMSTATS_IMPORT_OPEN_GWAS.out.objects
    versions = BIOC_MUNGESUMSTATS_IMPORT_OPEN_GWAS.out.versions
}
