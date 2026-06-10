#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: kmcut — optimal_cutoff_exploratory
// Perform a fast exploratory search for optimal prognostic cutoffs without running the time-consuming permutation test.
// Input: survival_data.txt, example_genes.txt
// Container: quay.io/biocontainers/bioconductor-kmcut:1.4.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_KMCUT_OPTIMAL_CUTOFF_EXPLORATORY {
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
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load the required package
    library(kmcut)
    
    # Define the input file paths as specified by the user
    fdat <- "example_genes.txt"
    sdat <- "survival_data.txt"
    
    # Verify that the input files exist in the working directory
    if (!file.exists(fdat)) {
      stop(paste("Required input file missing:", fdat))
    }
    if (!file.exists(sdat)) {
      stop(paste("Required input file missing:", sdat))
    }
    
    # 1. Create a SummarizedExperiment object from the input files
    message("Creating SummarizedExperiment object...")
    se <- create_se_object(efile = fdat, sfile = sdat)
    
    # Save the constructed SummarizedExperiment object as an RDS file for downstream use
    saveRDS(se, file = "se_object.rds")
    message("Saved SummarizedExperiment object to 'se_object.rds'")
    
    # 2. Search for optimal cutoffs using the fast exploratory method (no permutation test)
    message("Running exploratory optimal cutoff search...")
    km_opt_scut(obj = se, bfname = "test", wpdf = FALSE, verbose = FALSE)
    
    # Verify and report the automatically generated output files
    # km_opt_scut automatically generates:
    # - [bfname]_KMopt_minf_0.10.txt (tab-delimited results)
    # - [bfname]_KMopt_minf_0.10_labels.csv (CSV with low/high sample labels)
    expected_txt <- "test_KMopt_minf_0.10.txt"
    expected_csv <- "test_KMopt_minf_0.10_labels.csv"
    
    if (file.exists(expected_txt)) {
      message(paste("Successfully generated results table:", expected_txt))
    } else {
      warning("Expected results table was not found.")
    }
    
    if (file.exists(expected_csv)) {
      message(paste("Successfully generated sample labels:", expected_csv))
    } else {
      warning("Expected sample labels CSV was not found.")
    }
    
    message("Pipeline completed successfully.")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_KMCUT_OPTIMAL_CUTOFF_EXPLORATORY":
        kmcut: \$(Rscript -e 'cat(as.character(packageVersion("kmcut")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_optimal_cutoff_exploratory.csv versions.yml
    """
}

workflow BIOC_KMCUT_OPTIMAL_CUTOFF_EXPLORATORY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ survival_data.txt, example_genes.txt ] ]

    main:
    BIOC_KMCUT_OPTIMAL_CUTOFF_EXPLORATORY(ch_input)

    emit:
    tables   = BIOC_KMCUT_OPTIMAL_CUTOFF_EXPLORATORY.out.tables
    plots    = BIOC_KMCUT_OPTIMAL_CUTOFF_EXPLORATORY.out.plots
    objects  = BIOC_KMCUT_OPTIMAL_CUTOFF_EXPLORATORY.out.objects
    versions = BIOC_KMCUT_OPTIMAL_CUTOFF_EXPLORATORY.out.versions
}
