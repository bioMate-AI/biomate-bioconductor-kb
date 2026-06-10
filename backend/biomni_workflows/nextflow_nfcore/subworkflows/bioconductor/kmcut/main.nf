#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: kmcut — optimal_cutoff_permutation
// Identify optimal prognostic cutoffs for features and estimate their statistical significance using a permutation test.
// Input: survival_data.txt, example_genes.txt
// Container: quay.io/biocontainers/bioconductor-kmcut:1.4.0--r45hdfd78af_0
// R packages: kmcut
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_KMCUT_OPTIMAL_CUTOFF_PERMUTATION {
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
    
    # Load the kmcut package
    library(kmcut)
    
    # Define input file paths in the working directory
    fdat <- "example_genes.txt"
    sdat <- "survival_data.txt"
    
    # Check if input files exist
    if (!file.exists(fdat)) {
      stop("Required input file 'example_genes.txt' is missing from the working directory.")
    }
    if (!file.exists(sdat)) {
      stop("Required input file 'survival_data.txt' is missing from the working directory.")
    }
    
    # Stage 1: Create a SummarizedExperiment object from the input files
    se <- create_se_object(efile = fdat, sfile = sdat)
    
    # Save the constructed SummarizedExperiment object as an RDS file
    saveRDS(se, file = "se_object.rds")
    
    # Stage 2: Run the permutation test and cutoff optimization
    # Using the exact documented function call and arguments
    km_opt_pcut(
      obj = se,
      bfname = "test",
      n_iter = 10,
      wlabels = TRUE,
      wpdf = FALSE,
      verbose = FALSE,
      nproc = 1
    )

    cat <<-END_VERSIONS > versions.yml
    "BIOC_KMCUT_OPTIMAL_CUTOFF_PERMUTATION":
        kmcut: \$(Rscript -e 'cat(as.character(packageVersion("kmcut")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_optimal_cutoff_permutation.csv versions.yml
    """
}

workflow BIOC_KMCUT_OPTIMAL_CUTOFF_PERMUTATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ survival_data.txt, example_genes.txt ] ]

    main:
    BIOC_KMCUT_OPTIMAL_CUTOFF_PERMUTATION(ch_input)

    emit:
    tables   = BIOC_KMCUT_OPTIMAL_CUTOFF_PERMUTATION.out.tables
    plots    = BIOC_KMCUT_OPTIMAL_CUTOFF_PERMUTATION.out.plots
    objects  = BIOC_KMCUT_OPTIMAL_CUTOFF_PERMUTATION.out.objects
    versions = BIOC_KMCUT_OPTIMAL_CUTOFF_PERMUTATION.out.versions
}
