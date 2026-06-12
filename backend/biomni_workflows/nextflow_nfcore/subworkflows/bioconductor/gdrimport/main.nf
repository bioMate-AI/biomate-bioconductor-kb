#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: gDRimport — mae_to_pharmacoset
// Convert a gDR-generated MultiAssayExperiment (MAE) object into a PharmacoGx PharmacoSet (PSet) object.
// Input: kyung2022mae/MAE_E2.qs2
// Container: quay.io/biocontainers/bioconductor-gdrimport:1.8.1--r45hdfd78af_0
// R packages: PharmacoGx, gDRimport, qs2
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GDRIMPORT_MAE_TO_PHARMACOSET {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-gdrimport:1.8.1--r45hdfd78af_0"

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
    .bm_deps <- c("PharmacoGx", "gDRimport", "qs2")
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
    library(gDRimport)
    library(qs2)
    library(PharmacoGx)
    
    # Define input file path
    input_file <- "kyung2022mae/MAE_E2.qs2"
    
    # Check if input file exists
    if (!file.exists(input_file)) {
      stop(paste("Required input file not found:", input_file))
    }
    
    # --- Load the MAE object using qs2::qs_read ---
    message("Loading MultiAssayExperiment object...")
    mae <- qs2::qs_read(input_file)
    
    # --- Convert the MAE object into a PharmacoSet object ---
    message("Converting MAE to PharmacoSet...")
    pset <- convert_MAE_to_PSet(mae, pset_name = "Kyung2022")
    
    # --- Extract the TreatmentResponseExperiment ---
    message("Extracting TreatmentResponseExperiment...")
    tre <- treatmentResponse(pset)
    
    # Save meaningful results to output files
    message("Saving outputs...")
    
    # Save the PharmacoSet object
    saveRDS(pset, file = "Kyung2022_PSet.rds")
    
    # Save the TreatmentResponseExperiment object
    saveRDS(tre, file = "Kyung2022_TRE.rds")
    
    # Extract and save treatment and sample metadata as CSV tables
    tryCatch({
      treatment_df <- PharmacoGx::treatmentInfo(pset)
      write.csv(treatment_df, file = "treatment_info.csv", row.names = TRUE)
    }, error = function(e) {
      message("Could not save treatment info: ", e\$message)
    })
    
    tryCatch({
      sample_df <- PharmacoGx::sampleInfo(pset)
      write.csv(sample_df, file = "sample_info.csv", row.names = TRUE)
    }, error = function(e) {
      message("Could not save sample info: ", e\$message)
    })
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_GDRIMPORT_MAE_TO_PHARMACOSET":',
        paste0('        gDRimport: ', as.character(packageVersion("gDRimport")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mae_to_pharmacoset.csv versions.yml
    """
}

workflow BIOC_GDRIMPORT_MAE_TO_PHARMACOSET_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ kyung2022mae/MAE_E2.qs2 ] ]

    main:
    BIOC_GDRIMPORT_MAE_TO_PHARMACOSET(ch_input)

    emit:
    tables   = BIOC_GDRIMPORT_MAE_TO_PHARMACOSET.out.tables
    plots    = BIOC_GDRIMPORT_MAE_TO_PHARMACOSET.out.plots
    objects  = BIOC_GDRIMPORT_MAE_TO_PHARMACOSET.out.objects
    versions = BIOC_GDRIMPORT_MAE_TO_PHARMACOSET.out.versions
}
