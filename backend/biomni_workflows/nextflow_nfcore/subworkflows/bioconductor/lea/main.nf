#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: LEA
// LEA is an R package dedicated to population genomics, landscape genomics and genotype-environment as
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/LEA/inst/doc/LEA.R
// Upstream  : knitr
// Downstream: none
//
// Install: BiocManager::install("LEA")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_LEA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-lea"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-lea:3.18.0--r44_0' :
        'quay.io/biocontainers/bioconductor-lea:3.18.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_lea_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_lea_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_lea_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(LEA)
    library(jsonlite)

    # --- Numeric [] ---
    # Key functions: sample, lfmm
    ---------------------------------------------------------------------
    # creation of a genotype matrix  with missing genotypes
    dat = as.numeric(tutorial.R)
    dat[sample(1:length(dat), 100)] <-  9
    dat <- matrix(dat, nrow = 50, ncol = 400)
    # --- Min [] ---
    # Key functions: entropy, impute, lfmm
    ---------------------------------------------------------------------
    # select the run with the lowest cross-entropy value
    best = which.min(cross.entropy(project.missing, K = 4))
    # Impute the missing genotypes
    # --- Pvalues [] ---
    # Key functions: pvalues
    ---------------------------------------------------------------------
    # compute adjusted p-values
    p = lfmm.pvalues(project, K = 6)
    pvalues = p$pvalues
    # --- Data [] ---
    # Key functions: lfmm2
    ---------------------------------------------------------------------
    # load simulated data
    data("offset_example")
    # 200 diploid individuals genotyped at 510 SNP
    Y <- offset_example$geno
    # --- Matrix [] ---
    # Key functions: rnorm, sample, runif
    ---------------------------------------------------------------------
    # Simulate non-null effect sizes for 10 target loci
    #individuals
    n = 100
    #loci
    # --- Tcrossprod [] ---
    # Key functions: tcrossprod, rnorm
    ---------------------------------------------------------------------
    # Simulate a matrix containing haploid genotypes
    Y <-  tcrossprod(as.matrix(X), B) +
          tcrossprod(U, V) +
          matrix(rnorm(n*L, sd = .5), nrow = n)
    # --- Lfmm2 [] ---
    # Key functions: lfmm2
    ---------------------------------------------------------------------
    # Fitting an LFMM with K = 3 factors
    mod <- lfmm2(input = Y, env = X, K = 3)
    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    data("offset_example")
    Y <- offset_example$geno
    X <- offset_example$env
    X.pred <- offset_example$env.pred
    # --- Gap [] ---
    # Key functions: gap
    ---------------------------------------------------------------------

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_lea_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_lea_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_lea_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_LEA:", paste0("    lea: ", packageVersion("LEA"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_lea_results.csv
    touch ${prefix}_lea_output.rds
    echo "BIOC_LEA:" > versions.yml
    echo "    lea: 0.0.0" >> versions.yml
    """
}


workflow BIOC_LEA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_LEA(ch_input)

    emit:
    results  = BIOC_LEA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_LEA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_LEA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_LEA.out.versions  // channel: path(versions.yml)
}
