#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: rbec — contamination_detection
// Predict contaminated samples based on the recruitment ratio of sequencing reads across samples.
// Input: log_files
// Container: quay.io/biocontainers/bioconductor-rbec:1.18.0--r45ha27e39d_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RBEC_CONTAMINATION_DETECTION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-rbec:1.18.0--r45ha27e39d_0"

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
    .bm_deps <- c("Rbec")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required library
    library(Rbec)
    
    # 1. Compile paths of Rbec log files into a single text file
    # Read user-provided log files from the working directory
    if (dir.exists("log_files")) {
      log_path <- list.files("log_files", recursive = TRUE, full.names = TRUE)
    } else {
      log_path <- list.files(".", pattern = "\\.log\$", recursive = TRUE, full.names = TRUE)
    }
    
    if (length(log_path) == 0) {
      stop("Error: No Rbec log files found. Please place them in a 'log_files' directory or the working directory.")
    }
    
    log_file <- tempfile()
    writeLines(log_path, log_file)
    
    # Track files in tempdir before running to identify new outputs
    temp_dir_before <- list.files(tempdir(), recursive = TRUE, full.names = TRUE)
    
    # 2. Run Contam_detect to identify contaminated samples and generate a distribution plot
    Contam_detect(log_file, tempdir())
    
    # Identify and copy generated outputs to the working directory
    temp_dir_after <- list.files(tempdir(), recursive = TRUE, full.names = TRUE)
    new_files <- setdiff(temp_dir_after, temp_dir_before)
    
    if (length(new_files) > 0) {
      for (f in new_files) {
        dest <- file.path(".", basename(f))
        file.copy(f, dest, overwrite = TRUE)
        message("Saved output: ", dest)
      }
    } else {
      # Fallback: copy any PDF or CSV files generated in the temp directory
      fallback_files <- list.files(tempdir(), pattern = "\\.(pdf|csv|txt)\$", full.names = TRUE)
      for (f in fallback_files) {
        dest <- file.path(".", basename(f))
        file.copy(f, dest, overwrite = TRUE)
        message("Saved output: ", dest)
      }
    }

    cat <<-END_VERSIONS > versions.yml
    "BIOC_RBEC_CONTAMINATION_DETECTION":
        rbec: \$(Rscript -e 'cat(as.character(packageVersion("rbec")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_contamination_detection.csv versions.yml
    """
}

workflow BIOC_RBEC_CONTAMINATION_DETECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ log_files ] ]

    main:
    BIOC_RBEC_CONTAMINATION_DETECTION(ch_input)

    emit:
    tables   = BIOC_RBEC_CONTAMINATION_DETECTION.out.tables
    plots    = BIOC_RBEC_CONTAMINATION_DETECTION.out.plots
    objects  = BIOC_RBEC_CONTAMINATION_DETECTION.out.objects
    versions = BIOC_RBEC_CONTAMINATION_DETECTION.out.versions
}
