#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: abseqr — custom_downstream_comparison
// Combine and compare specific samples from different runs or subsets using the S4 plus operator and generate a refined comparative report.
// Input: samples
// Container: quay.io/biocontainers/bioconductor-abseqr:1.28.0--r45hdfd78af_0
// R packages: abseqR
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ABSEQR_CUSTOM_DOWNSTREAM_COMPARISON {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-abseqr:1.28.0--r45hdfd78af_0"

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
    .bm_deps <- c("abseqR")
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
    library(abseqR)
    
    # Define the input file path in the working directory
    input_file <- "samples.rds"
    
    # Check if the input file exists
    if (!file.exists(input_file)) {
      stop(paste("Required input file", input_file, "not found in the working directory."))
    }
    
    # Load the samples (named list of AbSeqRep S4 objects)
    samples <- readRDS(input_file)
    
    # Verify that the required samples exist in the loaded object
    required_samples <- c("PCR1", "PCR3")
    missing_samples <- setdiff(required_samples, names(samples))
    if (length(missing_samples) > 0) {
      stop(paste("Missing required sample(s) in the input list:", paste(missing_samples, collapse = ", ")))
    }
    
    # Set the sandbox directory to the current working directory
    sandboxDirectory <- getwd()
    
    # 1. Combine individual sample objects using the + operator
    pcr1.pcr3 <- samples[["PCR1"]] + samples[["PCR3"]]
    
    # 2. Run the report function on the combined object to generate a standalone comparative HTML report
    refinedComparison <- report(pcr1.pcr3,
                                outputDir = file.path(sandboxDirectory,
                                                      "refined_comparison"),
                                report = 1)
    
    # Save the resulting S4 object to an RDS file
    output_file <- "refined_comparison_result.rds"
    saveRDS(refinedComparison, file = output_file)

    cat <<-END_VERSIONS > versions.yml
    "BIOC_ABSEQR_CUSTOM_DOWNSTREAM_COMPARISON":
        abseqr: \$(Rscript -e 'cat(as.character(packageVersion("abseqr")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_custom_downstream_comparison.csv versions.yml
    """
}

workflow BIOC_ABSEQR_CUSTOM_DOWNSTREAM_COMPARISON_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ samples ] ]

    main:
    BIOC_ABSEQR_CUSTOM_DOWNSTREAM_COMPARISON(ch_input)

    emit:
    tables   = BIOC_ABSEQR_CUSTOM_DOWNSTREAM_COMPARISON.out.tables
    plots    = BIOC_ABSEQR_CUSTOM_DOWNSTREAM_COMPARISON.out.plots
    objects  = BIOC_ABSEQR_CUSTOM_DOWNSTREAM_COMPARISON.out.objects
    versions = BIOC_ABSEQR_CUSTOM_DOWNSTREAM_COMPARISON.out.versions
}
