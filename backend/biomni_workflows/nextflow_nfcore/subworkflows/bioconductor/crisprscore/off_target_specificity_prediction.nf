#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: crisprscore — off_target_specificity_prediction
// Predict off-target specificity of gRNAs against potential genomic off-target sites using MIT and CFD scoring.
// Input: spacers.txt, protospacers.txt, pams.txt
// Container: quay.io/biocontainers/bioconductor-crisprscore:1.14.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CRISPRSCORE_OFF_TARGET_SPECIFICITY_PREDICTION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-crisprscore:1.14.0--r45hdfd78af_0"

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
    .bm_deps <- c("crisprScore")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load the required Bioconductor package
    library(crisprScore)
    
    # 1. Define spacer, protospacer, and PAM sequences by reading from user input files
    spacer <- readLines("spacers.txt", warn = FALSE)
    spacer <- trimws(spacer)
    spacer <- spacer[spacer != ""]
    
    protospacers <- readLines("protospacers.txt", warn = FALSE)
    protospacers <- trimws(protospacers)
    protospacers <- protospacers[protospacers != ""]
    
    pams <- readLines("pams.txt", warn = FALSE)
    pams <- trimws(pams)
    pams <- pams[pams != ""]
    
    # 2. Calculate MIT scores using getMITScores
    mit_results <- getMITScores(spacers=spacer,
                                protospacers=protospacers,
                                pams=pams)
    
    # 3. Calculate CFD scores using getCFDScores
    cfd_results <- getCFDScores(spacers=spacer,
                                protospacers=protospacers,
                                pams=pams)
    
    # Write the meaningful results to output CSV files
    write.csv(mit_results, file = "mit_scores.csv", row.names = FALSE)
    write.csv(cfd_results, file = "cfd_scores.csv", row.names = FALSE)

    cat <<-END_VERSIONS > versions.yml
    "BIOC_CRISPRSCORE_OFF_TARGET_SPECIFICITY_PREDICTION":
        crisprscore: \$(Rscript -e 'cat(as.character(packageVersion("crisprscore")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_off_target_specificity_prediction.csv versions.yml
    """
}

workflow BIOC_CRISPRSCORE_OFF_TARGET_SPECIFICITY_PREDICTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ spacers.txt, protospacers.txt, pams.txt ] ]

    main:
    BIOC_CRISPRSCORE_OFF_TARGET_SPECIFICITY_PREDICTION(ch_input)

    emit:
    tables   = BIOC_CRISPRSCORE_OFF_TARGET_SPECIFICITY_PREDICTION.out.tables
    plots    = BIOC_CRISPRSCORE_OFF_TARGET_SPECIFICITY_PREDICTION.out.plots
    objects  = BIOC_CRISPRSCORE_OFF_TARGET_SPECIFICITY_PREDICTION.out.objects
    versions = BIOC_CRISPRSCORE_OFF_TARGET_SPECIFICITY_PREDICTION.out.versions
}
