#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: stageR — differential_transcript_usage
// Perform stage-wise testing for differential transcript usage (DTU) mapping transcripts to genes using the stageRTx class.
// Input: pScreen, pConfirmation, tx2gene
// Container: quay.io/biocontainers/bioconductor-stager:1.32.0--r45hdfd78af_0
// R packages: stageR
// Bioconductor: 3.20 | R: 4.4
// Requires: stageR
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Filter out transcripts belonging to genes that were removed during independent filtering
//  * 2. [Input & Preparation] Construct the stageRTx object using stageRTx()
//  * 3. [Core Analysis] Perform stage-wise adjustment using stageWiseAdjustment() with method="dtu"
//  * 4. [Core Analysis] Retrieve significant genes using getSignificantGenes()
//  * 5. [Core Analysis] Retrieve significant transcripts using getSignificantTx()
//  * 6. [Core Analysis] Retrieve adjusted p-values using getAdjustedPValues()

nextflow.enable.dsl = 2

process BIOC_STAGER_DIFFERENTIAL_TRANSCRIPT_USAGE {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("stageR")
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
        
    library(stageR)
    
    # 1. Read User Inputs from the working directory
    if (file.exists("pScreen.rds")) {
      pScreen <- readRDS("pScreen.rds")
    } else if (file.exists("pScreen.csv")) {
      df_pscreen <- read.csv("pScreen.csv", header = TRUE)
      pScreen <- setNames(df_pscreen[[2]], df_pscreen[[1]])
    } else {
      stop("Error: pScreen file (pScreen.rds or pScreen.csv) not found in the working directory.")
    }
    
    if (file.exists("pConfirmation.rds")) {
      pConfirmation <- readRDS("pConfirmation.rds")
    } else if (file.exists("pConfirmation.csv")) {
      df_pconf <- read.csv("pConfirmation.csv", header = TRUE)
      pConfirmation <- matrix(df_pconf[[2]], ncol = 1, dimnames = list(df_pconf[[1]], "transcript"))
    } else {
      stop("Error: pConfirmation file (pConfirmation.rds or pConfirmation.csv) not found in the working directory.")
    }
    
    if (file.exists("tx2gene.rds")) {
      tx2gene <- readRDS("tx2gene.rds")
    } else if (file.exists("tx2gene.csv")) {
      tx2gene <- read.csv("tx2gene.csv", header = TRUE, stringsAsFactors = FALSE)
    } else {
      stop("Error: tx2gene file (tx2gene.rds or tx2gene.csv) not found in the working directory.")
    }
    
    # 2. Execute Documented Code
    rowsNotFiltered <- tx2gene[, 2] %in% names(pScreen)
    tx2gene <- tx2gene[rowsNotFiltered, , drop = FALSE]
    
    valid_tx <- intersect(tx2gene[, 1], rownames(pConfirmation))
    tx2gene <- tx2gene[match(valid_tx, tx2gene[, 1]), , drop = FALSE]
    pConfirmation <- pConfirmation[valid_tx, , drop = FALSE]
    
    stageRObj <- stageRTx(pScreen=pScreen, pConfirmation=pConfirmation, pScreenAdjusted=TRUE, tx2gene=tx2gene)
    stageRObj <- stageWiseAdjustment(object=stageRObj, method="dtu", alpha=0.05)
    
    # Retrieve results
    sigGenes <- getSignificantGenes(stageRObj)
    sigTx <- getSignificantTx(stageRObj)
    padj <- getAdjustedPValues(stageRObj, order=TRUE, onlySignificantGenes=FALSE)
    
    # Print heads to stdout as in documented code
    print(head(sigGenes))
    print(head(sigTx))
    print(head(padj))
    
    # 3. Write Outputs
    write.csv(as.data.frame(sigGenes), "significant_genes.csv", row.names = TRUE)
    write.csv(as.data.frame(sigTx), "significant_transcripts.csv", row.names = TRUE)
    write.csv(as.data.frame(padj), "adjusted_pvalues.csv", row.names = FALSE)
    saveRDS(stageRObj, "stageRObj.rds")

    writeLines(c(
        '"BIOC_STAGER_DIFFERENTIAL_TRANSCRIPT_USAGE":',
        paste0('    stageR: ', as.character(packageVersion('stageR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_differential_transcript_usage.csv versions.yml
    """
}

workflow BIOC_STAGER_DIFFERENTIAL_TRANSCRIPT_USAGE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ pScreen, pConfirmation, tx2gene ] ]

    main:
    BIOC_STAGER_DIFFERENTIAL_TRANSCRIPT_USAGE(ch_input)

    emit:
    tables   = BIOC_STAGER_DIFFERENTIAL_TRANSCRIPT_USAGE.out.tables
    plots    = BIOC_STAGER_DIFFERENTIAL_TRANSCRIPT_USAGE.out.plots
    objects  = BIOC_STAGER_DIFFERENTIAL_TRANSCRIPT_USAGE.out.objects
    versions = BIOC_STAGER_DIFFERENTIAL_TRANSCRIPT_USAGE.out.versions
}
