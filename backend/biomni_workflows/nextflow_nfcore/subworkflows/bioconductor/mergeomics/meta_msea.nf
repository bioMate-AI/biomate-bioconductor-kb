#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: mergeomics — meta_msea
// Perform meta-analysis at the pathway or network level across multiple independent MSEA runs.
// Input: job.msea1, job.msea2, job.msea3
// Container: quay.io/biocontainers/bioconductor-mergeomics:1.38.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MERGEOMICS_META_MSEA {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-mergeomics:1.38.0--r45hdfd78af_0"

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
    .bm_deps <- c("Mergeomics")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load the required library
    library(Mergeomics)
    
    # Read the completed MSEA job objects from the working directory
    # These are expected to be saved as RDS files named exactly as specified
    job.msea1 <- readRDS("job.msea1")
    job.msea2 <- readRDS("job.msea2")
    job.msea3 <- readRDS("job.msea3")
    
    # 1. Combine MSEA job objects into a list
    job.metamsea = list()
    job.metamsea\$job1 = job.msea1
    job.metamsea\$job2 = job.msea2
    job.metamsea\$job3 = job.msea3
    
    # 2. Run meta-analysis using ssea.meta
    job.metamsea = ssea.meta(job.metamsea,"meta_label",
    "meta_folder")
    
    # Save the final meta-MSEA job object
    saveRDS(job.metamsea, file = "job.metamsea.rds")
    
    # If the meta-analysis results contain a data frame, export it as a CSV
    if (!is.null(job.metamsea\$results)) {
      write.csv(job.metamsea\$results, file = "meta_msea_results.csv", row.names = FALSE)
    }

    cat <<-END_VERSIONS > versions.yml
    "BIOC_MERGEOMICS_META_MSEA":
        mergeomics: \$(Rscript -e 'cat(as.character(packageVersion("mergeomics")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_meta_msea.csv versions.yml
    """
}

workflow BIOC_MERGEOMICS_META_MSEA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ job.msea1, job.msea2, job.msea3 ] ]

    main:
    BIOC_MERGEOMICS_META_MSEA(ch_input)

    emit:
    tables   = BIOC_MERGEOMICS_META_MSEA.out.tables
    plots    = BIOC_MERGEOMICS_META_MSEA.out.plots
    objects  = BIOC_MERGEOMICS_META_MSEA.out.objects
    versions = BIOC_MERGEOMICS_META_MSEA.out.versions
}
