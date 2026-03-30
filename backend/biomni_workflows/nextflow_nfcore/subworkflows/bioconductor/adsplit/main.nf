#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: adSplit
// This package implements clustering of microarray gene expression profiles according to functional an
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/adSplit/inst/doc/tr_2005_02.R
// Upstream  : golubEsets
// Downstream: none
//
// Install: BiocManager::install("adSplit")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ADSPLIT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-adsplit"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-adsplit:1.76.0--r44_0' :
        'quay.io/biocontainers/bioconductor-adsplit:1.76.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_adsplit_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_adsplit_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_adsplit_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(adSplit)
    library(jsonlite)

    # --- Exit [] ---
    # Key functions: exit, interactive
    library(golubEsets)
    oldopt <- options(digits=3)
    on.exit( {options(oldopt)} )
    options(width=70)
    if (interactive()) {
    # --- Data [] ---
    # Key functions: data
    library(golubEsets)
    data(Golub_Merge)
    # --- Exprs [] ---
    # Key functions: exprs, diana2means
    e <- exprs(Golub_Merge)
    vars <- apply(e, 1, var)
    e <- e[vars > quantile(vars,0.9),]
    diana2means(e)
    diana2means(e, return.cut=TRUE)
    # --- diana2means [] ---
    # Key functions: diana2means
    x <- diana2means(e, return.cut=TRUE)
    x$cut
    # --- Adsplit [] ---
    # Key functions: adSplit
    adSplit(Golub_Merge, "GO:0006915", "hu6800")
    # --- make E I D2 P R O B E Senv [] ---
    # Key functions: makeEID2PROBESenv
    EID2PSenv <- makeEID2PROBESenv(hu6800ENTREZID)
    # --- Drawrandomps [] ---
    # Key functions: drawRandomPS
    drawRandomPS(10, EID2PSenv, ls(EID2PSenv))
    # --- random Diana2means [] ---
    # Key functions: randomDiana2means, exprs
    scores <- randomDiana2means(20, exprs(Golub_Merge), "hu6800", ndraws = 1000)
    # --- Adsplit [] ---
    # Key functions: adSplit
    glutamSplits <- adSplit(Golub_Merge, "KEGG:00251", "hu6800", B=1000)
    # --- Data [] ---
    # Key functions: data
    data(golubKEGGSplits)
    print(golubKEGGSplits)
    summary(golubKEGGSplits$qvalues)
    # --- Image [] ---
    # Key functions: image
    image(golubKEGGSplits, filter.fdr=0.3, outfile="splitSet.eps", res=300)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_adsplit_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_adsplit_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_adsplit_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ADSPLIT:", paste0("    adsplit: ", packageVersion("adSplit"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_adsplit_results.csv
    touch ${prefix}_adsplit_output.rds
    echo "BIOC_ADSPLIT:" > versions.yml
    echo "    adsplit: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ADSPLIT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ADSPLIT(ch_input)

    emit:
    results  = BIOC_ADSPLIT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ADSPLIT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ADSPLIT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ADSPLIT.out.versions  // channel: path(versions.yml)
}
