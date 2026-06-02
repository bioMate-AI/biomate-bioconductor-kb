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

    # --- Principal Component Analysis [] ---
    # Key functions: pca, tracy.widom
    pc <- pca("genotypes.lfmm", scale = TRUE)
    tw <- tracy.widom(pc)
    plot(tw$percentage, pch = 19, col = "darkblue", cex = 0.8)


    # --- Population Structure Inference [] ---
    # Key functions: snmf, cross.entropy, barchart, snmf.pvalues
    project <- snmf("genotypes.geno", K = 1:5, entropy = TRUE,
                    repetitions = 5, project = "new")
    best <- which.min(cross.entropy(project, K = 4))
    bp <- barchart(project, K = 4, run = best, border = NA, space = 0)
    p <- snmf.pvalues(project, entropy = TRUE, ploidy = 2, K = 4)


    # --- Missing Genotype Imputation [] ---
    # Key functions: snmf, impute, read.lfmm
    project.missing <- snmf("genoM.lfmm", K = 4, entropy = TRUE,
                            repetitions = 5, project = "new")
    best <- which.min(cross.entropy(project.missing, K = 4))
    impute(project.missing, "genoM.lfmm", method = "mode", K = 4,
           run = best)
    dat.imp <- read.lfmm("genoM.lfmm_imputed.lfmm")


    # --- Latent Factor Mixed Models [] ---
    # Key functions: lfmm, lfmm.pvalues
    project <- lfmm("genotypes.lfmm", "gradients.env", K = 6,
                    repetitions = 5, project = "new")
    p <- lfmm.pvalues(project, K = 6)
    pvalues <- p$pvalues
    hist(pvalues, col = "lightblue")


    # --- Association Testing with LFMM2 [] ---
    # Key functions: lfmm2, lfmm2.test
    data("offset_example")
    Y <- offset_example$geno
    X <- offset_example$env
    mod.lfmm2 <- lfmm2(input = Y, env = X, K = 2)
    pv <- lfmm2.test(object = mod.lfmm2, input = Y, env = X, full = TRUE)
    plot(-log10(pv$pvalues), col = "grey", cex = 0.5, pch = 19)

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
