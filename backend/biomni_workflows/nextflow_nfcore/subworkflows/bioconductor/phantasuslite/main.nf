#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: phantasusLite
// PhantasusLite – a lightweight package with helper functions of general interest extracted from phant
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/phantasusLite/inst/doc/phantasusLite-tutorial.R
// Upstream  : GEOquery
// Downstream: none
//
// Install: BiocManager::install("phantasusLite")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PHANTASUSLITE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-phantasuslite"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-phantasuslite:1.4.0--r44_0' :
        'quay.io/biocontainers/bioconductor-phantasuslite:1.4.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_phantasuslite_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_phantasuslite_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_phantasuslite_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(phantasusLite)
    library(jsonlite)

    # --- Head [] ---
    # Key functions: exprs
    ---------------------------------------------------------------------
    head(exprs(es))
    # --- Gethsdsfilelist [] ---
    # Key functions: getHSDSFileList
    ---------------------------------------------------------------------
    url <- 'https://alserglab.wustl.edu/hsds/?domain=/counts'
    getHSDSFileList(url)
    # --- load Counts From H5 File H S D S [] ---
    # Key functions: loadCountsFromH5FileHSDS, exprs
    ---------------------------------------------------------------------
    file <- "dee2/mmusculus_star_matrix_20240409.h5"
    es <- loadCountsFromH5FileHSDS(es, url, file)
    head(exprs(es))
    # --- Loadcountsfromhsds [] ---
    # Key functions: loadCountsFromHSDS, exprs
    ---------------------------------------------------------------------
    es <- ess[[1]]
    es <- loadCountsFromHSDS(es, url)
    head(exprs(es))
    # --- Preproc [] ---
    # Key functions: preproc, experimentData
    ---------------------------------------------------------------------
    preproc(experimentData(es))$gene_counts_source
    # --- Head [] ---
    # Key functions: fData
    ---------------------------------------------------------------------
    head(fData(es))
    # --- Infercondition [] ---
    # Key functions: inferCondition
    ---------------------------------------------------------------------
    es <- inferCondition(es)
    print(es$condition)
    print(es$replicate)
    # --- Readgct [] ---
    # Key functions: readGct
    ---------------------------------------------------------------------
    es2 <- readGct(f)
    print(es2)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_phantasuslite_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_phantasuslite_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_phantasuslite_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PHANTASUSLITE:", paste0("    phantasuslite: ", packageVersion("phantasusLite"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_phantasuslite_results.csv
    touch ${prefix}_phantasuslite_output.rds
    echo "BIOC_PHANTASUSLITE:" > versions.yml
    echo "    phantasuslite: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PHANTASUSLITE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PHANTASUSLITE(ch_input)

    emit:
    results  = BIOC_PHANTASUSLITE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PHANTASUSLITE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PHANTASUSLITE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PHANTASUSLITE.out.versions  // channel: path(versions.yml)
}
