#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: PharmacoGx — gene_drug_association
// Model the association between molecular features (e.g., gene expression, mutations) and drug sensitivity.
// Input: CCLEsmall
// Container: quay.io/biocontainers/bioconductor-pharmacogx:3.14.0--r45ha27e39d_0
// R packages: PharmacoGx, pander
// Bioconductor: 3.20 | R: 4.4
// Requires: PharmacoGx, pander
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Identify features of interest. 2. Model gene-drug associations using drugSensitivitySig (linear regression adjusted for tissue and

nextflow.enable.dsl = 2

process BIOC_PHARMACOGX_GENE_DRUG_ASSOCIATION {
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
    .bm_deps <- c("PharmacoGx", "pander")
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
            library(PharmacoGx)
            library(pander)
            
            # Read the user input file 'CCLEsmall' from the working directory
            CCLEsmall <- NULL
            if (file.exists("CCLEsmall")) {
              CCLEsmall <- readRDS("CCLEsmall")
            } else if (file.exists("CCLEsmall.rds")) {
              CCLEsmall <- readRDS("CCLEsmall.rds")
            } else if (file.exists("CCLEsmall.RData")) {
              env <- new.env()
              load("CCLEsmall.RData", envir = env)
              for (obj_name in names(env)) {
                if (inherits(env[[obj_name]], "PharmacoSet") || inherits(env[[obj_name]], "PharmacoSet2")) {
                  CCLEsmall <- env[[obj_name]]
                  break
                }
              }
              if (is.null(CCLEsmall)) {
                CCLEsmall <- env[[names(env)[1]]]
              }
            } else {
              stop("Error: CCLEsmall file not found in the working directory. Please ensure 'CCLEsmall' (RDS or RData) is present.")
            }
            
            # 1. Identify features of interest
            features <- fNames(CCLEsmall, "rna")[ which(featureInfo(CCLEsmall, "rna")\$Symbol == "NQO1")]
            
            # 2. Model gene-drug associations using drugSensitivitySig
            sig.rna <- drugSensitivitySig(
              pSet=CCLEsmall, 
              mDataType="rna", 
              drugs=c("17-AAG"), 
              features=features, 
              sensitivity.measure="auc_published", 
              molecular.summary.stat="median", 
              sensitivity.summary.stat="median", 
              tissue=TRUE,
              batch=TRUE,
              verbose=FALSE
            )
            
            sig.mut <- drugSensitivitySig(
              pSet=CCLEsmall, 
              mDataType="mutation", 
              drugs=c("PD-0325901"), 
              features="BRAF", 
              sensitivity.measure="auc_published", 
              molecular.summary.stat="and", 
              sensitivity.summary.stat="median", 
              tissue=TRUE,
              batch=TRUE,
              verbose=FALSE
            )
            
            # Combine results
            # Safely extract 2D matrices (features x statistics) from the 3D arrays (features x drugs x statistics)
            mat.rna <- matrix(sig.rna, nrow=dim(sig.rna)[1], ncol=dim(sig.rna)[3], dimnames=list(dimnames(sig.rna)[[1]], dimnames(sig.rna)[[3]]))
            mat.mut <- matrix(sig.mut, nrow=dim(sig.mut)[1], ncol=dim(sig.mut)[3], dimnames=list(dimnames(sig.mut)[[1]], dimnames(sig.mut)[[3]]))
            
            sig <- rbind(mat.rna, mat.mut)
            rownames(sig) <- c(paste("17-AAG", features, sep=" + "), "PD-0325901 + BRAF")
            colnames(sig) <- dimnames(sig.mut)[[3]]
            
            # Print table to console
            pander::pandoc.table(t(sig), style = "rmarkdown", caption='P Value of Gene-Drug Association' )
            
            # Write outputs to files
            # Save the combined signature matrix as RDS
            saveRDS(sig, "gene_drug_association_sig.rds")
            
            # Save the transposed signature matrix as a CSV table
            write.csv(as.data.frame(t(sig)), "gene_drug_association_results.csv", row.names = TRUE)
            
            # Save the pandoc table output to a text file
            sink("gene_drug_association_table.txt")
            pander::pandoc.table(t(sig), style = "rmarkdown", caption='P Value of Gene-Drug Association' )
            sink()

    writeLines(c(
        '"BIOC_PHARMACOGX_GENE_DRUG_ASSOCIATION":',
        paste0('    PharmacoGx: ', as.character(packageVersion('PharmacoGx')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gene_drug_association.csv versions.yml
    """
}

workflow BIOC_PHARMACOGX_GENE_DRUG_ASSOCIATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ CCLEsmall ] ]

    main:
    BIOC_PHARMACOGX_GENE_DRUG_ASSOCIATION(ch_input)

    emit:
    tables   = BIOC_PHARMACOGX_GENE_DRUG_ASSOCIATION.out.tables
    plots    = BIOC_PHARMACOGX_GENE_DRUG_ASSOCIATION.out.plots
    objects  = BIOC_PHARMACOGX_GENE_DRUG_ASSOCIATION.out.objects
    versions = BIOC_PHARMACOGX_GENE_DRUG_ASSOCIATION.out.versions
}
