#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: DirichletMultinomial — generative_classification
// Classify metagenomic samples into phenotypic groups using supervised Dirichlet-Multinomial group models.
// Input: Twins.csv, TwinStudy.t
// Container: quay.io/biocontainers/bioconductor-dirichletmultinomial:1.52.0--r45h57f0213_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: DirichletMultinomial, lattice
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load count data and phenotypic labels
//  * 2. [Core Analysis] Subset counts by phenotype using csubset
//  * 3. [Core Analysis] Fit group-specific Dirichlet-Multinomial models using dmngroup
//  * 4. [Core Analysis] Predict sample phenotypes using predict
//  * 5. [Core Analysis] Perform cross-validation using cvdmngroup
//  * 6. [Visualization & Output] Evaluate classification performance using roc and plot ROC curves

nextflow.enable.dsl = 2

process BIOC_DIRICHLETMULTINOMIAL_GENERATIVE_CLASSIFICATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-metagenomics:3.20-deps"

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
    .bm_deps <- c("DirichletMultinomial", "lattice")
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
    library(DirichletMultinomial)
    library(lattice)
    library(parallel)
    
    # Set options and color palette
    options(width=70, digits=2)
    full <- TRUE
    .qualitative <- DirichletMultinomial:::.qualitative
    
    # 1. Load count data and phenotypic labels from the working directory
    count <- t(as.matrix(read.csv("Twins.csv", row.names=1)))
    
    # Fit single-group models to identify the 'best' model (needed for comparison later)
    fit <- mclapply(1:7, dmn, count=count, verbose=TRUE)
    lplc <- sapply(fit, laplace)
    best <- fit[[which.min(lplc)]]
    
    # Load phenotypic labels
    pheno_labels <- scan("TwinStudy.t", what="character")
    pheno <- factor(pheno_labels)
    names(pheno) <- rownames(count)
    
    # 2. Subset counts by phenotype using csubset
    counts <- lapply(levels(pheno), csubset, count, pheno)
    sapply(counts, dim)
    
    # 3. Fit group-specific Dirichlet-Multinomial models using dmngroup
    bestgrp <- dmngroup(
        count, pheno, k=1:5, verbose=TRUE, mc.preschedule=FALSE
    )
    saveRDS(bestgrp, file="bestgrp.rds")
    
    # Extract and save mixture weights
    mix_weights <- lapply(bestgrp, mixturewt)
    sink("mixture_weights.txt")
    print(mix_weights)
    sink()
    
    # Compare Laplace scores
    laplace_comparison <- c(
        sapply(bestgrp, laplace),
        'Combined' = sum(sapply(bestgrp, laplace)),
        Single = laplace(best)
    )
    write.csv(as.data.frame(as.list(laplace_comparison)), "laplace_comparison.csv", row.names=FALSE)
    
    # 4. Predict sample phenotypes using predict and export confusion matrix
    conf_matrix <- xtabs(~pheno + predict(bestgrp, count, assign=TRUE))
    write.csv(as.data.frame.matrix(conf_matrix), "confusion_matrix.csv")
    
    # 5. Perform cross-validation using cvdmngroup
    best_k <- sapply(bestgrp, function(x) nrow(mixturewt(x)))
    xval <- cvdmngroup(
        nrow(count), count, best_k, pheno,
        verbose=TRUE, mc.preschedule=FALSE
    )
    saveRDS(xval, file="xval.rds")
    
    # 6. Evaluate classification performance using roc and plot ROC curves
    target_level <- levels(pheno)[1]
    bst <- roc(pheno[rownames(count)] == target_level,
               predict(bestgrp, count)[, target_level])
    bst\$Label <- "Single"
    two <- roc(pheno[rownames(xval)] == target_level, xval[, target_level])
    two\$Label <- "Grouped"
    both <- rbind(bst, two)
    pars <- list(superpose.line=list(col=.qualitative[1:2], lwd=2))
    
    # Save ROC plot to PDF
    pdf("roc_curve.pdf", width=7, height=7)
    p <- xyplot(
        TruePostive ~ FalsePositive, group=Label, both,
        type="l", par.settings=pars,
        auto.key=list(lines=TRUE, points=FALSE, x=.6, y=.1),
        xlab="False Positive", ylab="True Positive"
    )
    print(p)
    dev.off()

    writeLines(c(
        '"BIOC_DIRICHLETMULTINOMIAL_GENERATIVE_CLASSIFICATION":',
        paste0('    DirichletMultinomial: ', as.character(packageVersion('DirichletMultinomial')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_generative_classification.csv versions.yml
    """
}

workflow BIOC_DIRICHLETMULTINOMIAL_GENERATIVE_CLASSIFICATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Twins.csv, TwinStudy.t ] ]

    main:
    BIOC_DIRICHLETMULTINOMIAL_GENERATIVE_CLASSIFICATION(ch_input)

    emit:
    tables   = BIOC_DIRICHLETMULTINOMIAL_GENERATIVE_CLASSIFICATION.out.tables
    plots    = BIOC_DIRICHLETMULTINOMIAL_GENERATIVE_CLASSIFICATION.out.plots
    objects  = BIOC_DIRICHLETMULTINOMIAL_GENERATIVE_CLASSIFICATION.out.objects
    versions = BIOC_DIRICHLETMULTINOMIAL_GENERATIVE_CLASSIFICATION.out.versions
}
