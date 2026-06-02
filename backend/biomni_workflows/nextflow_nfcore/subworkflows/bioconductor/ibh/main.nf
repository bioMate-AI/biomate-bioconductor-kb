#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ibh
// This package contains methods for calculating Interaction Based Homogeneity to evaluate fitness of g
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ibh/inst/doc/ibh.R
// Upstream  : simpIntLists, stats, yeastCC
// Downstream: none
//
// Install: BiocManager::install("ibh")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_IBH {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ibh"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ibh:1.54.0--r44_0' :
        'quay.io/biocontainers/bioconductor-ibh:1.54.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ibh_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ibh_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ibh_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ibh)
    library(jsonlite)

    # --- Ibhexample [] ---
    # Key functions: ibh
    library(ibh)
     data(ArabidopsisBioGRIDInteractionEntrezId)
     geneList <- list(839226, 817241, 824340, 832179, 818561, 831145,
         838782, 826404)
     ibh(ArabidopsisBioGRIDInteractionEntrezId, geneList)
    # --- Ibhbiogridexample1 [] ---
    # Key functions: ibhBioGRID
    geneList <- list(839226, 817241, 824340, 832179, 818561, 831145,
       838782, 826404)
    ibhBioGRID(geneList, organism = "arabidopsis", idType = "EntrezId")
    # --- Ibhbiogridexample2 [] ---
    # Key functions: ibhBioGRID
    geneList <- list("YJR151C", "YBL032W", "YAL040C", "YBL072C",
         "YCL050C", "YCR009C")
     ibhBioGRID(geneList, organism = "yeast", idType = "UniqueId")
    # --- Ibhformultiplegenelistsexample [] ---
    # Key functions: ibhForMultipleGeneLists
    data(ArabidopsisBioGRIDInteractionEntrezId)
     listofGeneList <- list(list(839226, 817241, 824340, 832179, 818561,
         831145, 838782, 826404), list(832018, 839226, 838824))
     ibhForMultipleGeneLists(ArabidopsisBioGRIDInteractionEntrezId,
         listofGeneList)
    # --- Ibhformultiplegenelistsbiogridexample [] ---
    # Key functions: ibhForMultipleGeneListsBioGRID
    listofGeneList <- list(list("YJR151C", "YBL032W", "YAL040C",
         "YBL072C", "YCL050C", "YCR009C"), list("YDR063W", "YDR074W",
         "YDR080W", "YDR247W", "YGR183C", "YHL033C"), list("YOL068C",
         "YOL015W", "YOL009C", "YOL004W", "YOR065W"))
    # --- Ibhclusterevalexample [] ---
    # Key functions: exprs, dist, kmeans, ibhClusterEval
    require(yeastCC)
     require(stats)
     data(yeastCC)
     require(simpIntLists)
     data(YeastBioGRIDInteractionUniqueId)
    # --- Ibhclusterevalbiogridexample [] ---
    # Key functions: ibhClusterEvalBioGRID
    ibhClusterEvalBioGRID(k$cluster, rownames(subset), organism = "yeast",
         idType = "UniqueId")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ibh_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ibh_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ibh_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_IBH:", paste0("    ibh: ", packageVersion("ibh"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ibh_results.csv
    touch ${prefix}_ibh_output.rds
    echo "BIOC_IBH:" > versions.yml
    echo "    ibh: 0.0.0" >> versions.yml
    """
}


workflow BIOC_IBH_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_IBH(ch_input)

    emit:
    results  = BIOC_IBH.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_IBH.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_IBH.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_IBH.out.versions  // channel: path(versions.yml)
}
