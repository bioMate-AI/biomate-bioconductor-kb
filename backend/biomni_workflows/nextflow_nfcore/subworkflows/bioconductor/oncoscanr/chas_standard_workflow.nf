#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: oncoscanr — chas_standard_workflow
// Run the complete standard analysis workflow on a ChAS export file using a single wrapper function.
// Input: chas_file.txt
// Container: quay.io/biocontainers/bioconductor-oncoscanr:1.12.0--r45hdfd78af_0
// R packages: jsonlite, oncoscanR
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ONCOSCANR_CHAS_STANDARD_WORKFLOW {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-oncoscanr:1.12.0--r45hdfd78af_0"

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
    .bm_deps <- c("jsonlite", "oncoscanR")
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
    library(oncoscanR)
    library(jsonlite)
    
    # Define the input file as specified by the user
    segs.filename <- "chas_file.txt"
    
    # Verify that the input file exists before running the workflow
    if (!file.exists(segs.filename)) {
      stop(paste("Error: Input file", segs.filename, "not found in the working directory."))
    }
    
    # Run the complete standard analysis workflow on the ChAS export file
    dat <- workflow_oncoscan.chas(segs.filename)
    
    # Display messages exactly as documented
    message(paste('Arms with copy loss:', 
                  paste(dat\$armlevel\$LOSS, collapse = ', ')))
    message(paste('Arms with copy gains:', 
                  paste(dat\$armlevel\$GAIN, collapse = ', ')))
    message(paste('HRD score:', dat\$scores\$HRD))
    
    # Write meaningful output files for downstream analysis
    # 1. Save the complete result list as an RDS object
    saveRDS(dat, "oncoscan_workflow_results.rds")
    
    # 2. Export the calculated scores to a CSV table
    scores_df <- data.frame(
      File = segs.filename,
      HRD = dat\$scores\$HRD,
      TDplus = dat\$scores\$TDplus,
      avgCN = dat\$scores\$avgCN,
      stringsAsFactors = FALSE
    )
    write.csv(scores_df, "oncoscan_scores.csv", row.names = FALSE)
    
    # 3. Export the arm-level alterations to a structured JSON file
    armlevel_json <- jsonlite::toJSON(dat\$armlevel, auto_unbox = TRUE, pretty = TRUE)
    writeLines(armlevel_json, "oncoscan_armlevel_alterations.json")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_ONCOSCANR_CHAS_STANDARD_WORKFLOW":
        oncoscanr: \$(Rscript -e 'cat(as.character(packageVersion("oncoscanr")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_chas_standard_workflow.csv versions.yml
    """
}

workflow BIOC_ONCOSCANR_CHAS_STANDARD_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ chas_file.txt ] ]

    main:
    BIOC_ONCOSCANR_CHAS_STANDARD_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_ONCOSCANR_CHAS_STANDARD_WORKFLOW.out.tables
    plots    = BIOC_ONCOSCANR_CHAS_STANDARD_WORKFLOW.out.plots
    objects  = BIOC_ONCOSCANR_CHAS_STANDARD_WORKFLOW.out.objects
    versions = BIOC_ONCOSCANR_CHAS_STANDARD_WORKFLOW.out.versions
}
