#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: mirlab — validate_specific_mirna_targets
// Predict miRNA-mRNA relationships and validate the top predicted targets of a specific miRNA against ground truth.
// Input: dataset.csv, groundtruth.csv
// Container: quay.io/biocontainers/bioconductor-mirlab:1.40.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MIRLAB_VALIDATE_SPECIFIC_MIRNA_TARGETS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-mirlab:1.40.0--r45hdfd78af_0"

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
    .bm_deps <- c("mirlab")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load the required library
    library(miRLAB)
    
    # Define the input file paths as specified by the user
    dataset <- "dataset.csv"
    groundtruth <- "groundtruth.csv"
    
    # 1. Predict miRNA-mRNA relationships using Pearson correlation
    pearson <- Pearson(dataset, 1:3, 4:18)
    
    # 2. Extract the top predicted targets for a specific miRNA (the 3rd miRNA, top 10 targets)
    miR200aTop10 <- bRank(pearson, 3, 10, TRUE)
    
    # 3. Validate the top predicted targets against the ground truth
    miR200aTop10Confirmed <- Validation(miR200aTop10, groundtruth)
    
    # Save the results to output files
    write.csv(as.data.frame(miR200aTop10), "miR200aTop10.csv", row.names = TRUE)
    write.csv(as.data.frame(miR200aTop10Confirmed), "miR200aTop10Confirmed.csv", row.names = TRUE)
    saveRDS(pearson, "pearson_correlation_matrix.rds")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_MIRLAB_VALIDATE_SPECIFIC_MIRNA_TARGETS":
        mirlab: \$(Rscript -e 'cat(as.character(packageVersion("mirlab")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_validate_specific_mirna_targets.csv versions.yml
    """
}

workflow BIOC_MIRLAB_VALIDATE_SPECIFIC_MIRNA_TARGETS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ dataset.csv, groundtruth.csv ] ]

    main:
    BIOC_MIRLAB_VALIDATE_SPECIFIC_MIRNA_TARGETS(ch_input)

    emit:
    tables   = BIOC_MIRLAB_VALIDATE_SPECIFIC_MIRNA_TARGETS.out.tables
    plots    = BIOC_MIRLAB_VALIDATE_SPECIFIC_MIRNA_TARGETS.out.plots
    objects  = BIOC_MIRLAB_VALIDATE_SPECIFIC_MIRNA_TARGETS.out.objects
    versions = BIOC_MIRLAB_VALIDATE_SPECIFIC_MIRNA_TARGETS.out.versions
}
