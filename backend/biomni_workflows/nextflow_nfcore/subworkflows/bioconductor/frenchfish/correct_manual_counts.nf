#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: frenchfish — correct_manual_counts
// Correct manually counted FISH spots across multiple probes using a Markov chain Monte Carlo Poisson model and nuclear volume correction.
// Input: manual_counts
// Container: quay.io/biocontainers/bioconductor-frenchfish:1.22.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FRENCHFISH_CORRECT_MANUAL_COUNTS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-frenchfish:1.22.0--r45hdfd78af_0"

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
    .bm_deps <- c("frenchFISH")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required library
    library(frenchFISH)
    
    # Set seed for reproducibility (essential for the MCMC Poisson model)
    set.seed(366)
    
    # 1. Read the manual counts matrix from the working directory
    # The input file 'manual_counts.csv' must have columns representing probes and rows representing nuclei
    if (!file.exists("manual_counts.csv")) {
      stop("Error: 'manual_counts.csv' not found in the working directory.")
    }
    
    manual_counts_df <- read.csv("manual_counts.csv", check.names = FALSE)
    manual_counts <- as.matrix(manual_counts_df)
    
    # 2. Run the manual counts estimation model using getManualCountsEstimates
    # with specified nuclear radius and section height
    nuclear_radius <- 8
    section_height <- 4
    
    corrected_manual_counts <- getManualCountsEstimates(manual_counts, 
                                                        nuclear_radius, 
                                                        section_height)
    
    # 3. Print the corrected spot counts at different percentiles
    print(corrected_manual_counts)
    
    # 4. Write named output files for the results
    write.csv(corrected_manual_counts, "corrected_manual_counts.csv", row.names = FALSE)
    saveRDS(corrected_manual_counts, "corrected_manual_counts.rds")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_FRENCHFISH_CORRECT_MANUAL_COUNTS":
        frenchfish: \$(Rscript -e 'cat(as.character(packageVersion("frenchfish")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_correct_manual_counts.csv versions.yml
    """
}

workflow BIOC_FRENCHFISH_CORRECT_MANUAL_COUNTS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ manual_counts ] ]

    main:
    BIOC_FRENCHFISH_CORRECT_MANUAL_COUNTS(ch_input)

    emit:
    tables   = BIOC_FRENCHFISH_CORRECT_MANUAL_COUNTS.out.tables
    plots    = BIOC_FRENCHFISH_CORRECT_MANUAL_COUNTS.out.plots
    objects  = BIOC_FRENCHFISH_CORRECT_MANUAL_COUNTS.out.objects
    versions = BIOC_FRENCHFISH_CORRECT_MANUAL_COUNTS.out.versions
}
