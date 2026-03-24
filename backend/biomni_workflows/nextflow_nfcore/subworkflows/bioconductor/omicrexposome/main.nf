#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: omicRexposome
// omicRexposome systematizes the association evaluation between exposures and omic data, taking advant
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/omicRexposome/inst/doc/exposome_omic_integration.R
// Upstream  : MultiDataSet, rexposome
// Downstream: none
//
// Install: BiocManager::install("omicRexposome")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_OMICREXPOSOME {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-omicrexposome"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-omicrexposome:1.28.0--r44_0' :
        'quay.io/biocontainers/bioconductor-omicrexposome:1.28.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_omicrexposome_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_omicrexposome_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_omicrexposome_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(omicRexposome)
    library(jsonlite)

    # --- Expos Data [] ---
    # Key functions: data, class
    data("brge_expo", package = "brgedata")
    class(brge_expo)
    # --- Gexp Data [] ---
    # Key functions: data
    data("brge_gexp", package = "brgedata")
    # --- Gexp Analysis [] ---
    # Key functions: createMultiDataSet, add_genexp, add_exp, association
    mds <- createMultiDataSet()
    mds <- add_genexp(mds, brge_gexp)
    mds <- add_exp(mds, brge_expo)
    gexp <- association(mds, formula=~Sex+Age,
        expset = "exposures", omicset = "expression")
    # --- Gexp Tables [] ---
    # Key functions: tableHits, tableLambda
    hit <- tableHits(gexp, th=0.001)
    lab <- tableLambda(gexp)
    merge(hit, lab, by="exposure")
    # --- Gexp Analysis Sva [] ---
    # Key functions: association
    gexp <- association(mds, formula=~Sex+Age,
        expset = "exposures", omicset = "expression", sva = "fast")
    # --- Gexp Tables Sva [] ---
    # Key functions: tableHits, tableLambda
    hit <- tableHits(gexp, th=0.001)
    lab <- tableLambda(gexp)
    merge(hit, lab, by="exposure")
    # --- Gexp Plot Qq [] ---
    # Key functions: arrange, plotAssociation, ggtitle
    gridExtra::grid.arrange(
        plotAssociation(gexp, rid="Ben_p", type="qq") +
            ggplot2::ggtitle("Transcriptome - Pb Association"),
        plotAssociation(gexp, rid="BPA_p", type="qq") +
            ggplot2::ggtitle("Transcriptome - THM Association"),
    # --- Gexp Plot Volcano [] ---
    # Key functions: arrange, plotAssociation, ggtitle
    gridExtra::grid.arrange(
        plotAssociation(gexp, rid="Ben_p", type="volcano", tPV=-log10(1e-04)) +
            ggplot2::ggtitle("Transcriptome - Pb Association"),
        plotAssociation(gexp, rid="BPA_p", type="volcano", tPV=-log10(1e-04)) +
            ggplot2::ggtitle("Transcriptome - THM Association"),
    # --- Prot Data [] ---
    # Key functions: data
    data("brge_prot", package="brgedata")
    brge_prot
    # --- Prot Analysis [] ---
    # Key functions: createMultiDataSet, add_eset, add_exp, association
    mds <- createMultiDataSet()
    mds <- add_eset(mds, brge_prot, dataset.type  ="proteome")
    mds <- add_exp(mds, brge_expo)
    prot <- association(mds, formula=~Sex+Age,
        expset = "exposures", omicset = "proteome")
    # --- Prot Hits [] ---
    # Key functions: tableHits
    tableHits(prot, th=0.001)
    # --- Prot Plot Volcano [] ---
    # Key functions: arrange, plotAssociation, ggtitle, geom_hline
    gridExtra::grid.arrange(
        plotAssociation(prot, rid="Ben_p", type="protein") +
            ggplot2::ggtitle("Proteome - Cd Association") +
            ggplot2::geom_hline(yintercept = 1, color = "LightPink"),
        plotAssociation(prot, rid="NO2_p", type="protein") +
    # --- Missing Exp [] ---
    # Key functions: plotMissings
    library(rexposome)
    plotMissings(brge_expo, set = "exposures")
    # --- Impute Exp [] ---
    # Key functions: imputation
    brge_expo <- imputation(brge_expo)
    # --- Crossomics Mcia [] ---
    # Key functions: createMultiDataSet, add_genexp, add_eset, add_exp, crossomics
    mds <- createMultiDataSet()
    mds <- add_genexp(mds, brge_gexp)
    mds <- add_eset(mds, brge_prot, dataset.type = "proteome")
    mds <- add_exp(mds, brge_expo)
    cr_mcia <- crossomics(mds, method = "mcia", verbose = TRUE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_omicrexposome_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_omicrexposome_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_omicrexposome_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_OMICREXPOSOME:", paste0("    omicrexposome: ", packageVersion("omicRexposome"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_omicrexposome_results.csv
    touch ${prefix}_omicrexposome_output.rds
    echo "BIOC_OMICREXPOSOME:" > versions.yml
    echo "    omicrexposome: 0.0.0" >> versions.yml
    """
}


workflow BIOC_OMICREXPOSOME_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_OMICREXPOSOME(ch_input)

    emit:
    results  = BIOC_OMICREXPOSOME.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_OMICREXPOSOME.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_OMICREXPOSOME.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_OMICREXPOSOME.out.versions  // channel: path(versions.yml)
}
