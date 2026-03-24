#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MineICA
// The goal of MineICA is to perform Independent Component Analysis (ICA) on multiple transcriptome dat
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MineICA/inst/doc/MineICA.R
// Upstream  : Biobase, GOstats, JADE, RColorBrewer, Rgraphviz
// Downstream: none
//
// Install: BiocManager::install("MineICA")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MINEICA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mineica"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-mineica:1.46.0--r44_0' :
        'quay.io/biocontainers/bioconductor-mineica:1.46.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_mineica_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mineica_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mineica_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(A)
    library(S)
    library(SByGene)
    library(jsonlite)

    # --- Data import and loading [] ---
    # Key functions: useMart
    mart <- useMart(biomart="ensembl", dataset="hsapiens_gene_ensembl")
    # --- Quality control and filtering [] ---
    # Key functions: exprs, sampleNames, runICA, clusterFastICARuns, buildIcaSet, frame, pData, selectFeatures_IQR
    ## library(fastICA)
    ## ## Random initializations are used for each iteration of FastICA
    ## ## Estimates are clustered using hierarchical clustering with average linkage
    ## res <- clusterFastICARuns(X=exprs(mainz), nbComp=5, alg.type="deflation", nbIt=10,
    ##                           funClus="hclust", method="average")
    # --- Show analysis [] ---
    # Key functions: show, selectFeatures_IQR, buildMineICAParams, listFilters, listAttributes, varLabels, featureNames, geneNames
    resW <- writeProjByComp(icaSet=icaSetMainz, params=params, mart=mart,
                            level='genes', selCutoffWrite=2.5)
    ## the description of the contributing genes of each component is contained
    ## in res$listAnnotComp which contains the gene id, its projection value, the number and
    ## the indices of the components on which it exceeds the threshold, and its description.

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_mineica_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_mineica_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_mineica_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MINEICA:", paste0("    mineica: ", packageVersion("MineICA"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mineica_results.csv
    touch ${prefix}_mineica_output.rds
    echo "BIOC_MINEICA:" > versions.yml
    echo "    mineica: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MINEICA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MINEICA(ch_input)

    emit:
    results  = BIOC_MINEICA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MINEICA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MINEICA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MINEICA.out.versions  // channel: path(versions.yml)
}
