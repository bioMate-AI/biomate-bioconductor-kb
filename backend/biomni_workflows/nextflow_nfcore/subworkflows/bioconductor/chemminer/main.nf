#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ChemmineR
// ChemmineR is a cheminformatics package for analyzing drug-like small molecule data in R. Its latest 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ChemmineR/inst/doc/ChemmineR.R
// Upstream  : RCurl, fmcsR, gplots, rgl, scatterplot3d
// Downstream: eiR, fmcsR, ChemmineDrugs
//
// Install: BiocManager::install("ChemmineR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CHEMMINER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-chemminer"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-chemminer:3.58.0--r44_0' :
        'quay.io/biocontainers/bioconductor-chemminer:3.58.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_chemminer_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_chemminer_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_chemminer_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ChemmineR)
    library(SDFDataTable)
    library(jsonlite)

    # --- Property Extraction and Matrix Conversion [] ---
    # Key functions: datablock, datablock2ma, splitNumChar, MW, MF
    blockmatrix <- datablock2ma(datablocklist=datablock(sdfset))
    numchar <- splitNumChar(blockmatrix=blockmatrix)
    propma <- data.frame(
        MF=MF(sdfset), 
        MW=MW(sdfset), 
        atomcountMA(sdfset)
    )
    datablock(sdfset) <- propma


    # --- Compound Clustering and Similarity Search [] ---
    # Key functions: cmp.search, cmp.cluster
    data(apset)
    search_res <- cmp.search(
        apset, 
        apset[1], 
        type=3, 
        cutoff=0.3, 
        quiet=TRUE
    )
    clust_res <- cmp.cluster(
        db=apset, 
        cutoff=c(0.65, 0.5), 
        quiet=TRUE
    )


    # --- Database Storage and Querying [] ---
    # Key functions: initDb, loadSdf, rings, findCompounds, getCompounds
    conn <- initDb("test.db")
    ids <- loadSdf(conn, sdfset, function(s) {
        data.frame(rings(s, type="count", upper=6, arom=TRUE))
    })
    results <- findCompounds(conn, "rings", c("rings <= 1"))
    compounds <- getCompounds(conn, results, keepOrder=TRUE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_chemminer_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_chemminer_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_chemminer_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CHEMMINER:", paste0("    chemminer: ", packageVersion("ChemmineR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_chemminer_results.csv
    touch ${prefix}_chemminer_output.rds
    echo "BIOC_CHEMMINER:" > versions.yml
    echo "    chemminer: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CHEMMINER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CHEMMINER(ch_input)

    emit:
    results  = BIOC_CHEMMINER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CHEMMINER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CHEMMINER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CHEMMINER.out.versions  // channel: path(versions.yml)
}
