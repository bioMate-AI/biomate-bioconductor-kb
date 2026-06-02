#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: RegEnrich
// This package is a pipeline to identify the key gene regulators in a biological process, for example 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/RegEnrich/inst/doc/RegEnrich.R
// Upstream  : BiocParallel, GEOquery, affy, annotate
// Downstream: none
//
// Install: BiocManager::install("RegEnrich")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_REGENRICH {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-regenrich"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-regenrich:1.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-regenrich:1.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_regenrich_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_regenrich_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_regenrich_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(RegEnrich)
    library(jsonlite)

    # --- quickExample simpler [] ---
    # Key functions: regenrich_network, regenrich_enrich, regenrich_rankScore
    object = regenrich_diffExpr(object) %>%
    regenrich_network() %>%
    regenrich_enrich() %>%
    # --- user defined network1 [] ---
    # Key functions: regenrich_network
    network_user = results_topNet(object)
    print(class(network_user))
    regenrich_network(object2) = network_user
    # --- user defined network edges [] ---
    # Key functions: regenrich_network
    network_user = slot(results_topNet(object), "elementset")
    print(class(network_user))
    regenrich_network(object2) = as.data.frame(network_user)
    # --- comparingFET GSEA [] ---
    # Key functions: plotOrders
    plotOrders(enrich_FET[[1]][1:20], enrich_GSEA[[1]][1:20])
    # --- regenrich rankScore [] ---
    # Key functions: results_score
    object = regenrich_rankScore(object)
    results_score(object)
    # --- plot Reg Tar Expr [] ---
    # Key functions: plotRegTarExpr
    plotRegTarExpr(object, reg = "ARNTL2")
    # --- case1ReadData1 1 [] ---
    # Key functions: rma, featureNames, getSYMBOL, fData
    library(affy)
    abatch = ReadAffy(celfile.path = "./GSE31193_RAW/")
    eset <- rma(abatch)
    # --- case1ReadData1 2 [] ---
    # Key functions: getGEO
    if (!requireNamespace("GEOquery"))
    BiocManager::install("GEOquery")
    library(GEOquery)
    # --- case1ReadData1 3 [] ---
    # Key functions: pData
    pd0 = pData(eset)
    pd = pd0[, c("title", "time:ch1", "agent:ch1")]
    colnames(pd) = c("title", "time", "group")
    # --- regenrich_network [] ---
    # Key functions: regenrich_network, regenrich_enrich, regenrich_rankScore
    expressionMatrix = exprs(data) # expression data
    rownames(expressionMatrix) = probeGene_noDu$`Gene Symbol`
    sampleInfo = pData(data) # sample information
    # --- plot Reg Tar Expr [] ---
    # Key functions: plotRegTarExpr
    plotRegTarExpr(object, reg = "STAT1")
    # --- Fetch GEO dataset [] ---
    # Key functions: getGEO, pData
    library(GEOquery)
    eset <- getGEO(GEO = "GSE130567")[[1]]
    pdata = pData(eset)[, c("title", "geo_accession", "cultured in:ch1", "treatment:ch1")]
    # --- untar [] ---
    # Key functions: untar
    tmpFolder = tempdir()
    tmpFile = tempfile(pattern = "GSE130567_", tmpdir = tmpFolder, fileext = ".tar")
    # --- close [] ---
    # Key functions: close
    dat = list()
    # --- regenrich_network [] ---
    # Key functions: regenrich_network, regenrich_enrich, regenrich_rankScore
    expressionMatrix = as.matrix(edata) # expression data
    data(TFs)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_regenrich_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_regenrich_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_regenrich_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_REGENRICH:", paste0("    regenrich: ", packageVersion("RegEnrich"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_regenrich_results.csv
    touch ${prefix}_regenrich_output.rds
    echo "BIOC_REGENRICH:" > versions.yml
    echo "    regenrich: 0.0.0" >> versions.yml
    """
}


workflow BIOC_REGENRICH_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_REGENRICH(ch_input)

    emit:
    results  = BIOC_REGENRICH.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_REGENRICH.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_REGENRICH.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_REGENRICH.out.versions  // channel: path(versions.yml)
}
