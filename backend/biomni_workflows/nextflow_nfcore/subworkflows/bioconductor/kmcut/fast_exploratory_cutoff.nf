#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: kmcut — fast_exploratory_cutoff
// Quickly identify optimal stratification cutoffs without running the time-consuming permutation test.
// Input: example_genes.txt, survival_data.txt
// Container: quay.io/biocontainers/bioconductor-kmcut:1.4.0--r45hdfd78af_0
// R packages: kmcut
// Bioconductor: 3.20 | R: 4.4
// Requires: kmcut
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Create a SummarizedExperiment object from the input files using create_se_object
//  * 2. [Visualization & Output] Run km_opt_scut to find optimal cutoffs and generate Kaplan-Meier curves and output files

nextflow.enable.dsl = 2

process BIOC_KMCUT_FAST_EXPLORATORY_CUTOFF {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
        
        # Define input file paths in the working directory
        fdat <- "example_genes.txt"
        sdat <- "survival_data.txt"
        
        # Verify input files exist
        if (!file.exists(fdat)) {
          stop("Error: Input file 'example_genes.txt' not found in the working directory.")
        }
        if (!file.exists(sdat)) {
          stop("Error: Input file 'survival_data.txt' not found in the working directory.")
        }
        
        # 1. Create a SummarizedExperiment object from the input files
        se <- create_se_object(efile = fdat, sfile = sdat)
        
        # Save the constructed SummarizedExperiment object to an RDS file
        saveRDS(se, file = "se_object.rds")
        
        # 2. Run km_opt_scut to find optimal cutoffs and generate output files
        # This will automatically generate:
        # - "test_KMopt_minf_0.10.txt" (tab-delimited results)
        # - "test_KMopt_minf_0.10_labels.csv" (CSV file with low/high sample labels)
        # - "test_KMopt_minf_0.10.pdf" (PDF file with Kaplan-Meier curves)
        km_opt_scut(obj = se, bfname = "test", wpdf = TRUE, verbose = FALSE)

    writeLines(c(
        '"BIOC_KMCUT_FAST_EXPLORATORY_CUTOFF":',
        paste0('    kmcut: ', as.character(packageVersion('kmcut')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_fast_exploratory_cutoff.csv versions.yml
    """
}

workflow BIOC_KMCUT_FAST_EXPLORATORY_CUTOFF_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ example_genes.txt, survival_data.txt ] ]

    main:
    BIOC_KMCUT_FAST_EXPLORATORY_CUTOFF(ch_input)

    emit:
    tables   = BIOC_KMCUT_FAST_EXPLORATORY_CUTOFF.out.tables
    plots    = BIOC_KMCUT_FAST_EXPLORATORY_CUTOFF.out.plots
    objects  = BIOC_KMCUT_FAST_EXPLORATORY_CUTOFF.out.objects
    versions = BIOC_KMCUT_FAST_EXPLORATORY_CUTOFF.out.versions
}
