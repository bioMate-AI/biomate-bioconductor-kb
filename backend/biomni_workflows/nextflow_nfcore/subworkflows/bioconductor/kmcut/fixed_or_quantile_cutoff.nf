#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: kmcut — fixed_or_quantile_cutoff
// Stratify samples and calculate log-rank test p-values using a specified quantile or a fixed user-supplied cutoff value.
// Input: survival_data.txt, example_genes.txt
// Container: quay.io/biocontainers/bioconductor-kmcut:1.4.0--r45hdfd78af_0
// R packages: kmcut
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_KMCUT_FIXED_OR_QUANTILE_CUTOFF {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-kmcut:1.4.0--r45hdfd78af_0"

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
    .bm_deps <- c("kmcut")
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
    
    # Load the required package
    library(kmcut)
    
    # Define the input file paths as specified by the user
    fdat <- "example_genes.txt"
    sdat <- "survival_data.txt"
    
    # Verify that the required input files exist in the working directory
    if (!file.exists(fdat)) {
      stop(paste("Required input file missing:", fdat))
    }
    if (!file.exists(sdat)) {
      stop(paste("Required input file missing:", sdat))
    }
    
    # 1. Create a SummarizedExperiment object from the input files
    message("Creating SummarizedExperiment object...")
    se <- create_se_object(efile = fdat, sfile = sdat)
    
    # 2. Stratify samples using a quantile cutoff (50th percentile / median)
    message("Running km_qcut with 50th quantile...")
    km_qcut(obj = se, bfname = "test", quant = 50, wpdf = FALSE)
    
    # 3. Stratify samples using a fixed user-defined cutoff (cutoff = 5)
    message("Running km_ucut with fixed cutoff of 5...")
    km_ucut(obj = se, bfname = "test", cutoff = 5, min_uval = 90, wpdf = FALSE)
    
    message("Pipeline completed successfully.")
    message("Outputs generated:")
    message("  - test_KM_quant_50.txt")
    message("  - test_KM_quant_50_labels.csv")
    message("  - test_KM_ucut_5.txt")
    message("  - test_KM_ucut_5_labels.csv")

    writeLines(c(
        '"BIOC_KMCUT_FIXED_OR_QUANTILE_CUTOFF":',
        paste0('        kmcut: ', as.character(packageVersion("kmcut")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_fixed_or_quantile_cutoff.csv versions.yml
    """
}

workflow BIOC_KMCUT_FIXED_OR_QUANTILE_CUTOFF_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ survival_data.txt, example_genes.txt ] ]

    main:
    BIOC_KMCUT_FIXED_OR_QUANTILE_CUTOFF(ch_input)

    emit:
    tables   = BIOC_KMCUT_FIXED_OR_QUANTILE_CUTOFF.out.tables
    plots    = BIOC_KMCUT_FIXED_OR_QUANTILE_CUTOFF.out.plots
    objects  = BIOC_KMCUT_FIXED_OR_QUANTILE_CUTOFF.out.objects
    versions = BIOC_KMCUT_FIXED_OR_QUANTILE_CUTOFF.out.versions
}
