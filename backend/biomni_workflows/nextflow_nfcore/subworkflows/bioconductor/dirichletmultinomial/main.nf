#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: DirichletMultinomial — unsupervised_clustering
// Cluster metagenomic samples into unsupervised Dirichlet components and analyze taxonomic contributions.
// Input: Twins.csv
// Container: quay.io/biocontainers/bioconductor-dirichletmultinomial:1.52.0--r45h57f0213_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: DirichletMultinomial, lattice
// Visualizations: density plot, scatter matrix, heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load and transpose count data to samples x taxa
//  * 2. [Core Analysis] Fit Dirichlet-Multinomial models for a range of components (k) using dmn
//  * 3. [Core Analysis] Select the best model using laplace, AIC, or BIC
//  * 4. [Core Analysis] Extract mixture weights and sample-to-component probabilities using mixturewt and mixture
//  * 5. [Visualization & Output] Analyze taxonomic contributions using fitted and visualize with heatmapdmn

nextflow.enable.dsl = 2

process BIOC_DIRICHLETMULTINOMIAL_UNSUPERVISED_CLUSTERING {
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
        
        # Set options and qualitative colors
        options(width=70, digits=2)
        .qualitative <- DirichletMultinomial:::.qualitative
        
        # 1. Load and transpose count data to samples x taxa
        # Expects "Twins.csv" in the working directory (taxa as rows, samples as columns)
        count <- t(as.matrix(read.csv("Twins.csv", row.names=1)))
        
        # Plot taxon representation and save to PDF
        cnts <- log10(colSums(count))
        pdf("taxon_representation_density.pdf")
        print(densityplot(
            cnts, xlim=range(cnts),
            xlab="Taxon representation (log 10 count)"
        ))
        dev.off()
        
        # 2. Fit Dirichlet-Multinomial models for a range of components (k = 1 to 7)
        # Using mclapply for parallel fitting (falls back to serial on Windows)
        fit <- mclapply(1:7, dmn, count=count, verbose=TRUE)
        saveRDS(fit, file="dmn_fit_models.rds")
        
        # 3. Select the best model using laplace
        lplc <- sapply(fit, laplace)
        
        pdf("model_fit_laplace.pdf")
        plot(lplc, type="b", xlab="Number of Dirichlet Components", ylab="Model Fit")
        dev.off()
        
        best <- fit[[which.min(lplc)]]
        
        # 4. Extract mixture weights and sample-to-component probabilities
        mix_wt <- mixturewt(best)
        write.csv(mix_wt, "mixture_weights.csv", row.names=TRUE)
        
        mix_prob <- mixture(best)
        write.csv(mix_prob, "mixture_probabilities.csv", row.names=TRUE)
        
        # 5. Analyze taxonomic contributions and visualize
        pdf("fitted_splom.pdf")
        print(splom(log(fitted(best))))
        dev.off()
        
        p0 <- fitted(fit[[1]], scale=TRUE) # scale by theta
        p4 <- fitted(best, scale=TRUE)
        colnames(p4) <- paste("m", 1:ncol(p4), sep="")
        
        meandiff <- colSums(abs(p4 - as.vector(p0)))
        write.csv(as.data.frame(meandiff), "mean_difference.csv", row.names=TRUE)
        
        diff <- rowSums(abs(p4 - as.vector(p0)))
        o <- order(diff, decreasing=TRUE)
        cdiff <- cumsum(diff[o]) / sum(diff)
        df <- cbind(Mean=p0[o], p4[o,], diff=diff[o], cdiff)
        write.csv(df, "taxonomic_contributions.csv", row.names=TRUE)
        
        pdf("heatmap_dmn.pdf")
        heatmapdmn(count, fit[[1]], best, 30)
        dev.off()

    writeLines(c(
        '"BIOC_DIRICHLETMULTINOMIAL_UNSUPERVISED_CLUSTERING":',
        paste0('    DirichletMultinomial: ', as.character(packageVersion('DirichletMultinomial')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_unsupervised_clustering.csv versions.yml
    """
}

workflow BIOC_DIRICHLETMULTINOMIAL_UNSUPERVISED_CLUSTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Twins.csv ] ]

    main:
    BIOC_DIRICHLETMULTINOMIAL_UNSUPERVISED_CLUSTERING(ch_input)

    emit:
    tables   = BIOC_DIRICHLETMULTINOMIAL_UNSUPERVISED_CLUSTERING.out.tables
    plots    = BIOC_DIRICHLETMULTINOMIAL_UNSUPERVISED_CLUSTERING.out.plots
    objects  = BIOC_DIRICHLETMULTINOMIAL_UNSUPERVISED_CLUSTERING.out.objects
    versions = BIOC_DIRICHLETMULTINOMIAL_UNSUPERVISED_CLUSTERING.out.versions
}
