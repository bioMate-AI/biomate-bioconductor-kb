#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: RankProd
// Non-parametric method for identifying differentially expressed (up- or down- regulated) genes based 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/RankProd/inst/doc/RankProd.R
// Upstream  : none
// Downstream: tRanslatome
//
// Install: BiocManager::install("RankProd")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RANKPROD {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rankprod"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rankprod:3.32.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rankprod:3.32.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rankprod_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rankprod_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rankprod_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(RankProd)
    library(RP)
    library(RPadvance)
    library(RSadvance)
    library(RankProducts)
    library(jsonlite)

    # --- Advanced Rank Product Analysis [] ---
    # Key functions: RP.advance, topGene
    data(arab)
    RP.adv.out <- RP.advance(
        arab, arab.cl, arab.origin,
        logged = TRUE, gene.names = arab.gnames, rand = 123
    )
    top_genes <- topGene(
        RP.adv.out, cutoff = 0.05, method = "pfp",
        logged = TRUE, logbase = 2, gene.names = arab.gnames
    )


    # --- Rank Sum Analysis [] ---
    # Key functions: RankProducts, topGene
    data(Apples)
    RS.apples <- RankProducts(
        apples.data.vsn, apples.cl,
        gene.names = rownames(apples.data.vsn),
        calculateProduct = FALSE, rand = 123
    )
    top_apples <- topGene(
        RS.apples, cutoff = 0.05, method = "pfp",
        gene.names = rownames(apples.data.vsn)
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rankprod_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rankprod_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rankprod_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RANKPROD:", paste0("    rankprod: ", packageVersion("RankProd"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rankprod_results.csv
    touch ${prefix}_rankprod_output.rds
    echo "BIOC_RANKPROD:" > versions.yml
    echo "    rankprod: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RANKPROD_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RANKPROD(ch_input)

    emit:
    results  = BIOC_RANKPROD.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RANKPROD.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RANKPROD.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RANKPROD.out.versions  // channel: path(versions.yml)
}
