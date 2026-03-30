#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: clusterSeq
// Identification of clusters of co-expressed genes based on their expression across multiple (replicat
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/clusterSeq/inst/doc/clusterSeq.R
// Upstream  : baySeq
// Downstream: none
//
// Install: BiocManager::install("clusterSeq")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CLUSTERSEQ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-clusterseq"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-clusterseq:1.30.0--r44_0' :
        'quay.io/biocontainers/bioconductor-clusterseq:1.30.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_clusterseq_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_clusterseq_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_clusterseq_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(clusterSeq)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    data(ratThymus, package = "clusterSeq")
    head(ratThymus)
    # --- Getlibsizes [] ---
    # Key functions: getLibsizes
    library(baySeq)
      libsizes <- getLibsizes(data = ratThymus)
    # --- Log2 [] ---
    # Key functions: diag
    ratThymus[ratThymus == 0] <- 1
    normRT <- log2(ratThymus %*% diag(1/libsizes) * mean(libsizes))
    # --- Kcluster [] ---
    # Key functions: kCluster
    kClust <- kCluster(normRT, matrixFile = "kclust_matrix.txt.gz", B = 1000)
    head(kClust)
    # --- Makeclusters [] ---
    # Key functions: makeClusters
    mkClust <- makeClusters(kClust, normRT, threshold = 1)
    # --- Kcluster [] ---
    # Key functions: kCluster, makeClusters
    kClustR <- kCluster(normRT, replicates = replicates, matrixFile = "kclust_matrix_newForceReps.txt.gz", B = 1000)
    mkClustR <- makeClusters(kClustR, normRT, threshold = 1)
    # --- Makeclustersff [] ---
    # Key functions: makeClustersFF
    mkClustRC <- makeClustersFF("kclust_matrix_newForceReps.txt.gz", method = "complete", cut.height = 5)
    # --- Makecluster [] ---
    # Key functions: makeCluster, getPriors, getLikelihoods
    #cl <- makeCluster(4)
    #cD.ratThymus <- getPriors(cD.ratThymus, consensus = TRUE, cl = cl)
    #cD.ratThymus <- getLikelihoods(cD.ratThymus, cl = cl)
    data(cD.ratThymus, package = "clusterSeq")
    # --- Associateposteriors [] ---
    # Key functions: associatePosteriors, makeClusters
    cD.ratThymus <- cD.ratThymus[1:1000,]
    aM <- associatePosteriors(cD.ratThymus)
    sX <- makeClusters(aM, cD.ratThymus, threshold = 0.5)
    # --- Wallace [] ---
    # Key functions: wallace
    wallace(sX, mkClustRC)
    # --- Plotclusterbs [] ---
    # Key functions: plotCluster
    par(mfrow = c(2,3))
    plotCluster(sX[1:6], cD.ratThymus)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_clusterseq_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_clusterseq_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_clusterseq_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CLUSTERSEQ:", paste0("    clusterseq: ", packageVersion("clusterSeq"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_clusterseq_results.csv
    touch ${prefix}_clusterseq_output.rds
    echo "BIOC_CLUSTERSEQ:" > versions.yml
    echo "    clusterseq: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CLUSTERSEQ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CLUSTERSEQ(ch_input)

    emit:
    results  = BIOC_CLUSTERSEQ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CLUSTERSEQ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CLUSTERSEQ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CLUSTERSEQ.out.versions  // channel: path(versions.yml)
}
