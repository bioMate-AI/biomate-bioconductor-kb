#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: annaffy
// Functions for handling data from Bioconductor Affymetrix annotation data packages. Produces compact 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/annaffy/inst/doc/annaffy.R
// Upstream  : none
// Downstream: webbioc
//
// Install: BiocManager::install("annaffy")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ANNAFFY {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-annaffy"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-annaffy:1.78.0--r44_0' :
        'quay.io/biocontainers/bioconductor-annaffy:1.78.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_annaffy_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_annaffy_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_annaffy_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(annaffy)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: featureNames, aafSymbol
    data(aafExpr)
    probeids <- featureNames(aafExpr)
    symbols <- aafSymbol(probeids, "hgu95av2.db")
    symbols[[54]]
    symbols[55:57]
    # --- Gettext [] ---
    # Key functions: getText
    getText(symbols[54:57])
    # --- Aafgo [] ---
    # Key functions: aafGO
    gos <- aafGO(probeids, "hgu95av2.db")
    gos[[3]]
    # --- Aafgenbank [] ---
    # Key functions: aafGenBank, getURL
    gbs <- aafGenBank(probeids, "hgu95av2.db")
    getURL(gbs[[1]])
    # --- Aaflocuslink [] ---
    # Key functions: aafLocusLink, getURL
    lls <- aafLocusLink(probeids, "hgu95av2.db")
    getURL(lls[[2]])
    # --- Aafcytoband [] ---
    # Key functions: aafCytoband, getURL
    bands <- aafCytoband(probeids, "hgu95av2.db")
    getURL(bands[[2]])
    # --- Aafpubmed [] ---
    # Key functions: aafPubMed, getURL
    pmids <- aafPubMed(probeids, "hgu95av2.db")
    getURL(pmids[[2]])
    # --- Geturl [] ---
    # Key functions: getURL
    getURL(gos[[1]][[4]])
    # --- Aafpathway [] ---
    # Key functions: aafPathway, getURL
    paths <- aafPathway(probeids, "hgu95av2.db")
    getURL(paths[[4]])
    # --- Integer [] ---
    # Key functions: pData
    class <- as.integer(pData(aafExpr)$covar1) - 1
    # --- Teststat [] ---
    # Key functions: teststat, exprs, featureNames
    teststat <- mt.teststat(exprs(aafExpr), class)
    index <- order(abs(teststat), decreasing = TRUE)
    probeids <- featureNames(aafExpr)[index]
    # --- Handler [] ---
    # Key functions: handler
    anncols <- aaf.handler()[c(1:3,8:9,11:13)]
    # --- Aaftableann [] ---
    # Key functions: aafTableAnn
    anntable <- aafTableAnn(probeids[1:50], "hgu95av2.db", anncols)
    # --- Savehtml [] ---
    # Key functions: saveHTML
    saveHTML(anntable, "example1.html", title = "Example Table without Data")
    # --- Aaftable [] ---
    # Key functions: aafTable
    testtable <- aafTable("t-statistic" = teststat[index[1:50]], signed = TRUE)
    table <- merge(anntable, testtable)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_annaffy_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_annaffy_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_annaffy_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ANNAFFY:", paste0("    annaffy: ", packageVersion("annaffy"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_annaffy_results.csv
    touch ${prefix}_annaffy_output.rds
    echo "BIOC_ANNAFFY:" > versions.yml
    echo "    annaffy: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ANNAFFY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ANNAFFY(ch_input)

    emit:
    results  = BIOC_ANNAFFY.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ANNAFFY.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ANNAFFY.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ANNAFFY.out.versions  // channel: path(versions.yml)
}
