#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: NormqPCR — qpcr_normalization
// Normalize target gene expression using single or multiple reference genes and calculate relative expression ratios (2^-ddCq).
// Input: example.txt
// Container: quay.io/biocontainers/bioconductor-normqpcr:1.56.0--r45h575d39b_0
// R packages: NormqPCR, ReadqPCR
// Bioconductor: 3.20 | R: 4.4
// Requires: NormqPCR, ReadqPCR
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read qPCR data using read.taqman
//  * 2. [Input & Preparation] Define contrast matrix for case and control samples
//  * 3. [Core Analysis] Perform delta-delta Cq normalization using deltaDeltaCq with a single housekeeper
//  * 4. [Core Analysis] Perform delta-delta Cq normalization using deltaDeltaCq with multiple housekeepers

nextflow.enable.dsl = 2

process BIOC_NORMQPCR_QPCR_NORMALIZATION {
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
    .bm_deps <- c("NormqPCR", "ReadqPCR")
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
        
    # Load required libraries
    library(ReadqPCR)
    library(NormqPCR)
    
    # 1. Read qPCR data using read.taqman from the working directory
    taqman.example <- "example.txt"
    qPCRBatch.taqman <- read.taqman(taqman.example)
    
    # 2. Define contrast matrix for case and control samples
    sNames <- sampleNames(qPCRBatch.taqman)
    n_samples <- length(sNames)
    case_vec <- rep(0, n_samples)
    case_vec[seq_len(max(1, floor(n_samples / 2)))] <- 1
    control_vec <- 1 - case_vec
    
    contM <- cbind(case_vec, control_vec)
    colnames(contM) <- c("interestingPhenotype", "wildTypePhenotype")
    rownames(contM) <- sNames
    
    # 3. Perform delta-delta Cq normalization using deltaDeltaCq with a single housekeeper
    feats <- featureNames(qPCRBatch.taqman)
    hkg <- feats[1]
    
    ddCq.taqman <- deltaDeltaCq(
      qPCRBatch = qPCRBatch.taqman, 
      maxNACase = 1, 
      maxNAControl = 1, 
      hkg = hkg, 
      contrastM = contM, 
      case = "interestingPhenotype", 
      control = "wildTypePhenotype", 
      statCalc = "geom", 
      hkgCalc = "arith"
    )
    
    # 4. Perform delta-delta Cq normalization using deltaDeltaCq with multiple housekeepers
    hkgs <- feats[1:min(3, length(feats))]
    
    ddCq.gM.taqman <- deltaDeltaCq(
      qPCRBatch = qPCRBatch.taqman, 
      maxNACase = 1, 
      maxNAControl = 1, 
      hkgs = hkgs, 
      contrastM = contM, 
      case = "interestingPhenotype", 
      control = "wildTypePhenotype", 
      statCalc = "arith", 
      hkgCalc = "arith"
    )
    
    # Write outputs to files
    write.csv(ddCq.taqman, file = "ddCq_single_hkg.csv", row.names = FALSE)
    saveRDS(ddCq.taqman, file = "ddCq_single_hkg.rds")
    
    write.csv(ddCq.gM.taqman, file = "ddCq_multi_hkgs.csv", row.names = FALSE)
    saveRDS(ddCq.gM.taqman, file = "ddCq_multi_hkgs.rds")

    writeLines(c(
        '"BIOC_NORMQPCR_QPCR_NORMALIZATION":',
        paste0('    NormqPCR: ', as.character(packageVersion('NormqPCR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_qpcr_normalization.csv versions.yml
    """
}

workflow BIOC_NORMQPCR_QPCR_NORMALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ example.txt ] ]

    main:
    BIOC_NORMQPCR_QPCR_NORMALIZATION(ch_input)

    emit:
    tables   = BIOC_NORMQPCR_QPCR_NORMALIZATION.out.tables
    plots    = BIOC_NORMQPCR_QPCR_NORMALIZATION.out.plots
    objects  = BIOC_NORMQPCR_QPCR_NORMALIZATION.out.objects
    versions = BIOC_NORMQPCR_QPCR_NORMALIZATION.out.versions
}
