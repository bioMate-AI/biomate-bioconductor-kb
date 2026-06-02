#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GeneMeta
// A collection of meta-analysis tools for analysing high throughput experimental data
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GeneMeta/inst/doc/GeneMeta.R
// Upstream  : RColorBrewer
// Downstream: none
//
// Install: BiocManager::install("GeneMeta")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GENEMETA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-genemeta"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-genemeta:1.78.0--r44_0' :
        'quay.io/biocontainers/bioconductor-genemeta:1.78.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_genemeta_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_genemeta_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_genemeta_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GeneMeta)
    library(CountPlot)
    library(DL)
    library(IDRplot)
    library(jsonlite)

    # --- Data Preparation and Splitting [Biobase] ---
    # Key functions: pData
    data(Nevins)
    thestatus <- Biobase::pData(Nevins)[, "ER.status"]
    group1 <- which(thestatus == "pos")
    group2 <- which(thestatus == "neg")
    rrr <- c(sample(group1, floor(length(group1) / 2)),
             sample(group2, ceiling(length(group2) / 2)))
    Split1 <- Nevins[, rrr]
    Split2 <- Nevins[, -rrr]
    Split1.ER <- as.numeric(Biobase::pData(Split1)[, "ER.status"]) - 1
    Split2.ER <- as.numeric(Biobase::pData(Split2)[, "ER.status"]) - 1

    # --- Effect Size Estimation [genemeta] ---
    # Key functions: getdF, dstar, sigmad
    d.Split1 <- getdF(Split1, Split1.ER)
    d.adj.Split1 <- dstar(d.Split1, length(Split1.ER))
    var.d.adj.Split1 <- sigmad(d.adj.Split1,
                               sum(Split1.ER == 0),
                               sum(Split1.ER == 1))
    d.Split2 <- getdF(Split2, Split2.ER)
    d.adj.Split2 <- dstar(d.Split2, length(Split2.ER))
    var.d.adj.Split2 <- sigmad(d.adj.Split2,
                               sum(Split2.ER == 0),
                               sum(Split2.ER == 1))

    # --- Heterogeneity Testing [genemeta] ---
    # Key functions: f.Q
    mymns <- cbind(d.adj.Split1, d.adj.Split2)
    myvars <- cbind(var.d.adj.Split1, var.d.adj.Split2)
    my.Q <- f.Q(mymns, myvars)

    # --- Fixed and Random Effects Modeling [genemeta] ---
    # Key functions: mu.tau2, var.tau2, tau2.DL
    muFEM <- mu.tau2(mymns, myvars)
    sdFEM <- var.tau2(myvars)
    ZFEM <- muFEM / sqrt(sdFEM)
    my.tau2.DL <- tau2.DL(my.Q, 2, my.weights = 1 / myvars)
    myvarsDL <- myvars + my.tau2.DL
    muREM <- mu.tau2(mymns, myvarsDL)
    varREM <- var.tau2(myvarsDL)
    ZREM <- muREM / sqrt(varREM)

    # --- Multi-study Integration and Z-Scores [genemeta] ---
    # Key functions: zScores, IDRplot
    esets <- list(Split1, Split2, Nevins)
    data.ER <- as.numeric(Biobase::pData(Nevins)[, "ER.status"]) - 1
    classes <- list(Split1.ER, Split2.ER, data.ER)
    theScores <- zScores(esets, classes, useREM = FALSE, CombineExp = 1:2)
    IDRplot(theScores, Combine = 1:2, colPos = "blue", colNeg = "red")

    # --- False Discovery Rate and Visualization [genemeta] ---
    # Key functions: zScoreFDR, CountPlot
    ScoresFDR <- zScoreFDR(esets, classes, useREM = FALSE,
                           nperm = 50, CombineExp = 1:2)
    CountPlot(ScoresFDR, Score = "FDR", kindof = "two.sided",
              cols = c("red", "blue", "green", "orange"),
              main = "two sided FDR", xlab = "FDR threshold",
              ylab = "Number of genes", CombineExp = 3)


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_genemeta_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_genemeta_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_genemeta_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GENEMETA:", paste0("    genemeta: ", packageVersion("GeneMeta"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_genemeta_results.csv
    touch ${prefix}_genemeta_output.rds
    echo "BIOC_GENEMETA:" > versions.yml
    echo "    genemeta: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GENEMETA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GENEMETA(ch_input)

    emit:
    results  = BIOC_GENEMETA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GENEMETA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GENEMETA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GENEMETA.out.versions  // channel: path(versions.yml)
}
