#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: BayesKnockdown
// A simple, fast Bayesian method for computing posterior probabilities for relationships between a sin
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/BayesKnockdown/inst/doc/BayesKnockdown.R
// Upstream  : Biobase
// Downstream: none
//
// Install: BiocManager::install("BayesKnockdown")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BAYESKNOCKDOWN {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-bayesknockdown"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-bayesknockdown:1.32.0--r44_0' :
        'quay.io/biocontainers/bioconductor-bayesknockdown:1.32.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_bayesknockdown_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_bayesknockdown_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_bayesknockdown_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BayesKnockdown)
    library(jsonlite)

    # --- Simulatedex [] ---
    # Key functions: rnorm, BayesKnockdown
    library(BayesKnockdown);
    set.seed(1618);
    n <- 100;
    p <- 10;
    x <- rnorm(n);
    # --- Knockdownex [] ---
    # Key functions: BayesKnockdown
    data(lincs.kd);
    kdResult <- BayesKnockdown(lincs.kd[1,], lincs.kd[-1,], prior=0.0005);
    kdResult;
    barplot(kdResult, names.arg="", xlab="Target Gene",
            ylab="Posterior Probability", ylim=c(0,1));
    # --- Knockdownes [] ---
    # Key functions: es
    library(Biobase);
    data(sample.ExpressionSet);
    subset <- sample.ExpressionSet[1:10,];
    BayesKnockdown.es(subset, "AFFX-MurIL10_at");
    # --- rnorm [] ---
    # Key functions: rnorm, diffExp
    n1 <- 25;
    n2 <- 30;
    p <- 10;
    y1 <- matrix(nrow=p, data=rnorm(n1*p));
    y2 <- matrix(nrow=p, data=rnorm(n2*p));

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_bayesknockdown_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_bayesknockdown_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_bayesknockdown_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BAYESKNOCKDOWN:", paste0("    bayesknockdown: ", packageVersion("BayesKnockdown"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bayesknockdown_results.csv
    touch ${prefix}_bayesknockdown_output.rds
    echo "BIOC_BAYESKNOCKDOWN:" > versions.yml
    echo "    bayesknockdown: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BAYESKNOCKDOWN_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BAYESKNOCKDOWN(ch_input)

    emit:
    results  = BIOC_BAYESKNOCKDOWN.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BAYESKNOCKDOWN.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BAYESKNOCKDOWN.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BAYESKNOCKDOWN.out.versions  // channel: path(versions.yml)
}
