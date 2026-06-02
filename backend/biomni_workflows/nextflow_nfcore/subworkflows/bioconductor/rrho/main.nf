#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: RRHO
// The package is aimed at inference on the amount of agreement in two sorted lists using the Rank-Rank
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/RRHO/inst/doc/RRHO.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("RRHO")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RRHO {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rrho"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rrho:1.46.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rrho:1.46.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rrho_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rrho_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rrho_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(RRHO)
    library(Nominal)
    library(RRHOComparison)
    library(Vectorize)
    library(jsonlite)

    # --- Significance Testing and FWER Correction [] ---
    # Key functions: RRHO, pvalRRHO
    list.length <- 100
    list.names <- paste('Gene', 1:list.length, sep='')
    gene.list1 <- data.frame(list.names, sample(100))
    gene.list2 <- data.frame(list.names, sample(100))
    RRHO.example <- RRHO(
        gene.list1, gene.list2,
        BY=TRUE, alternative='enrichment'
    )
    pval.testing <- pvalRRHO(RRHO.example, 50)
    xs <- seq(0, 10, length=100)
    ecdf_vals <- Vectorize(pval.testing$FUN.ecdf)(xs)


    # --- Multi-List Comparison [] ---
    # Key functions: RRHOComparison
    size <- 500
    list1 <- data.frame(
        GeneIdentifier=paste('gen', 1:size, sep=''),
        RankingVal=-log(runif(size))
    )
    list2 <- data.frame(
        GeneIdentifier=paste('gen', 1:size, sep=''),
        RankingVal=-log(runif(size))
    )
    list3 <- data.frame(
        GeneIdentifier=paste('gen', 1:size, sep=''),
        RankingVal=-log(runif(size))
    )
    rrho.comparison <- RRHOComparison(
        list1, list2, list3,
        stepsize=10,
        labels=c("list1", "list2", "list3"),
        plots=FALSE,
        outputdir=tempdir()
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rrho_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rrho_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rrho_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RRHO:", paste0("    rrho: ", packageVersion("RRHO"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rrho_results.csv
    touch ${prefix}_rrho_output.rds
    echo "BIOC_RRHO:" > versions.yml
    echo "    rrho: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RRHO_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RRHO(ch_input)

    emit:
    results  = BIOC_RRHO.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RRHO.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RRHO.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RRHO.out.versions  // channel: path(versions.yml)
}
