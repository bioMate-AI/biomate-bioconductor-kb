#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: abseqr — multi_directory_comparison
// Compare all samples across two entirely different abseqPy output directories.
// Input: SRR_CTRL, SRR_EXP
// Container: quay.io/biocontainers/bioconductor-abseqr:1.28.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ABSEQR_MULTI_DIRECTORY_COMPARISON {
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
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(abseqR)
    
    # Verify that the required user input directories exist in the working directory
    if (!dir.exists("SRR_CTRL")) {
        stop("Error: Input directory 'SRR_CTRL' not found in the working directory.")
    }
    
    if (!dir.exists("SRR_EXP")) {
        stop("Error: Input directory 'SRR_EXP' not found in the working directory.")
    }
    
    # 1. Load S4 objects from the first abseqPy directory (Control)
    SRRControl <- abseqReport("SRR_CTRL")
    
    # 2. Load S4 objects from the second abseqPy directory (Experimental)
    SRRExp <- abseqReport("SRR_EXP")
    
    # 3. Combine all loaded samples using Reduce and the + operator
    all.samples <- Reduce("+", c(SRRControl, SRRExp))
    
    # 4. Generate a comparative report for the combined collection of samples
    report(all.samples, outputDir = "SRRControl_vs_SRRExp")
    
    # Save meaningful results as RDS objects for downstream analysis
    saveRDS(SRRControl, file = "SRRControl_loaded.rds")
    saveRDS(SRRExp, file = "SRRExp_loaded.rds")
    saveRDS(all.samples, file = "all_samples_combined.rds")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_ABSEQR_MULTI_DIRECTORY_COMPARISON":
        abseqr: \$(Rscript -e 'cat(as.character(packageVersion("abseqr")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multi_directory_comparison.csv versions.yml
    """
}

workflow BIOC_ABSEQR_MULTI_DIRECTORY_COMPARISON_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ SRR_CTRL, SRR_EXP ] ]

    main:
    BIOC_ABSEQR_MULTI_DIRECTORY_COMPARISON(ch_input)

    emit:
    tables   = BIOC_ABSEQR_MULTI_DIRECTORY_COMPARISON.out.tables
    plots    = BIOC_ABSEQR_MULTI_DIRECTORY_COMPARISON.out.plots
    objects  = BIOC_ABSEQR_MULTI_DIRECTORY_COMPARISON.out.objects
    versions = BIOC_ABSEQR_MULTI_DIRECTORY_COMPARISON.out.versions
}
