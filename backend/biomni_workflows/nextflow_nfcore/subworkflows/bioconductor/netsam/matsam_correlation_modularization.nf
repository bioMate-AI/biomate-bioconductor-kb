#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: netsam — matsam_correlation_modularization
// Construct a correlation network from an expression matrix, identify hierarchical modules, and find associations with sample features and GO terms in a single wo
// Input: expression.cct
// Container: quay.io/biocontainers/bioconductor-netsam:1.50.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_NETSAM_MATSAM_CORRELATION_MODULARIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-netsam:1.50.0--r45hdfd78af_0"

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
    .bm_deps <- c("NetSAM")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Check for required input files in the working directory
    input_mat <- "expression.cct"
    input_ann <- "sample_annotation.tsi"
    
    if (!file.exists(input_mat)) {
      stop(paste("Required input file missing:", input_mat))
    }
    if (!file.exists(input_ann)) {
      stop(paste("Required input file missing:", input_ann))
    }
    
    # Load the NetSAM library
    library("NetSAM")
    
    # Stage 1: Test the format of the input expression matrix and sample annotation data
    message("Testing input file formats...")
    formatedData <- testFileFormat(
      inputMat = input_mat,
      sampleAnn = input_ann,
      collapse_mode = "maxSD"
    )
    
    # Stage 2: Run MatSAM to construct the correlation network, identify modules,
    # and calculate feature/GO associations
    message("Running MatSAM analysis...")
    outputFileName <- paste(getwd(), "/MatSAM", sep = "")
    
    matModule <- MatSAM(
      inputMat = input_mat,
      sampleAnn = input_ann,
      outputFileName = outputFileName,
      outputFormat = "msm",
      organism = "hsapiens",
      map_to_symbol = FALSE,
      idType = "auto",
      collapse_mode = "maxSD",
      naPer = 0.7,
      meanPer = 0.8,
      varPer = 0.8,
      corrType = "spearman",
      matNetMethod = "rank",
      valueThr = 0.6,
      rankBest = 0.003,
      networkType = "signed",
      netFDRMethod = "BH",
      netFDRThr = 0.05,
      minModule = 0.003,
      stepIte = FALSE,
      maxStep = 4,
      moduleSigMethod = "cutoff",
      modularityThr = 0.2,
      ZRanNum = 10,
      PerRanNum = 100,
      ranSig = 0.05,
      idNumThr = (-1),
      nThreads = 3
    )
    
    # Save the resulting R objects to disk
    message("Saving R objects to disk...")
    saveRDS(formatedData, file = "formatedData.rds")
    saveRDS(matModule, file = "matModule.rds")
    
    message("Pipeline completed successfully.")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_NETSAM_MATSAM_CORRELATION_MODULARIZATION":
        netsam: \$(Rscript -e 'cat(as.character(packageVersion("netsam")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_matsam_correlation_modularization.csv versions.yml
    """
}

workflow BIOC_NETSAM_MATSAM_CORRELATION_MODULARIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression.cct ] ]

    main:
    BIOC_NETSAM_MATSAM_CORRELATION_MODULARIZATION(ch_input)

    emit:
    tables   = BIOC_NETSAM_MATSAM_CORRELATION_MODULARIZATION.out.tables
    plots    = BIOC_NETSAM_MATSAM_CORRELATION_MODULARIZATION.out.plots
    objects  = BIOC_NETSAM_MATSAM_CORRELATION_MODULARIZATION.out.objects
    versions = BIOC_NETSAM_MATSAM_CORRELATION_MODULARIZATION.out.versions
}
