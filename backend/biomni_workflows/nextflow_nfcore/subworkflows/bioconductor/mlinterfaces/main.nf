#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MLInterfaces — supervised_classification_cv_fs
// Perform supervised classification on gene expression data with cross-validation and embedded feature selection to avoid selection bias.
// Input: fus
// Container: quay.io/biocontainers/bioconductor-mlinterfaces:1.90.0--r45ha27e39d_0
// R packages: Biobase, ALL, cluster, keggorthology, lattice, MASS, MLInterfaces
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, MLInterfaces
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Filter features non-specifically using Median Absolute Deviation (MAD)
//  * 2. [Core Analysis] Run MLearn with diagonal linear discriminant analysis (dldaI) and cross-validation (xvalSpec) containing embedded feature selectio
//  * 3. [Core Analysis] Assess classification performance using a confusion matrix (confuMat)

nextflow.enable.dsl = 2

process BIOC_MLINTERFACES_SUPERVISED_CLASSIFICATION_CV_FS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
    .bm_deps <- c("Biobase", "ALL", "cluster", "keggorthology", "lattice", "MASS", "MLInterfaces")
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
    library(MLInterfaces)
    library(Biobase)
    
    # Read the user input file 'fus' (ExpressionSet) from the working directory
    if (file.exists("fus")) {
      fus <- readRDS("fus")
    } else if (file.exists("fus.rds")) {
      fus <- readRDS("fus.rds")
    } else {
      stop("Required input file 'fus' or 'fus.rds' not found in the working directory.")
    }
    
    # 1. Filter features non-specifically using Median Absolute Deviation (MAD)
    mads = apply(exprs(fus),1,mad)
    fusk = fus[ mads > sort(mads,decr=TRUE)[300], ]
    
    # 2. Run MLearn with diagonal linear discriminant analysis (dldaI) and cross-validation (xvalSpec)
    # containing embedded feature selection (fs.absT)
    dldFS = MLearn( mol.biol~., fusk, dldaI, xvalSpec("LOG", 5, balKfold.xvspec(5), fs.absT(30) ))
    
    # 3. Assess classification performance using a confusion matrix
    cm = confuMat(dldFS)
    
    # Write outputs to the working directory
    # Save the confusion matrix as a CSV file
    write.csv(as.data.frame(cm), "confusion_matrix.csv", row.names = TRUE)
    
    # Save the MLearn classification output object
    saveRDS(dldFS, "dldFS_model.rds")
    
    # Save the filtered ExpressionSet object
    saveRDS(fusk, "fusk_filtered.rds")
    
    # Generate a PDF plot of the MADs distribution with the filtering threshold
    pdf("mads_distribution.pdf")
    hist(mads, breaks=50, main="Distribution of MADs across Genes", xlab="Median Absolute Deviation", col="skyblue")
    abline(v=sort(mads, decr=TRUE)[300], col="red", lty=2, lwd=2)
    legend("topright", legend="Top 300 Cutoff", col="red", lty=2, lwd=2)
    dev.off()

    writeLines(c(
        '"BIOC_MLINTERFACES_SUPERVISED_CLASSIFICATION_CV_FS":',
        paste0('    MLInterfaces: ', as.character(packageVersion('MLInterfaces')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_supervised_classification_cv_fs.csv versions.yml
    """
}

workflow BIOC_MLINTERFACES_SUPERVISED_CLASSIFICATION_CV_FS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ fus ] ]

    main:
    BIOC_MLINTERFACES_SUPERVISED_CLASSIFICATION_CV_FS(ch_input)

    emit:
    tables   = BIOC_MLINTERFACES_SUPERVISED_CLASSIFICATION_CV_FS.out.tables
    plots    = BIOC_MLINTERFACES_SUPERVISED_CLASSIFICATION_CV_FS.out.plots
    objects  = BIOC_MLINTERFACES_SUPERVISED_CLASSIFICATION_CV_FS.out.objects
    versions = BIOC_MLINTERFACES_SUPERVISED_CLASSIFICATION_CV_FS.out.versions
}
