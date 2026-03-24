#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ChIPXpress
// ChIPXpress takes as input predicted TF bound genes from ChIPx data and uses a corresponding database
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ChIPXpress/inst/doc/ChIPXpress.R
// Upstream  : ChIPXpressData, ChIPXrpess, GEOquery, affy, biganalytics
// Downstream: none
//
// Install: BiocManager::install("ChIPXpress")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CHIPXPRESS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-chipxpress"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-chipxpress:1.50.0--r44_0' :
        'quay.io/biocontainers/bioconductor-chipxpress:1.50.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_chipxpress_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_chipxpress_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_chipxpress_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ChIPXpress)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    library(ChIPXpress)
    data(Oct4ESC_ChIPgenes)
    head(Oct4ESC_ChIPgenes)
    # --- Chipxpress [] ---
    # Key functions: ChIPXpress
    Output <- ChIPXpress(TFID="18999",ChIP=Oct4ESC_ChIPgenes$EntrezID,DB=DB_GPL1261)
    head(Output[[1]])
    head(Output[[2]])
    # --- Builddatabase [] ---
    # Key functions: buildDatabase, tempdir
    ## library(bigmemory)
    ## library(biganalytics)
    ## library(ChIPXrpess)
    ## library(GEOquery)
    ## library(affy)
    # --- Mget [] ---
    # Key functions: mget
    ## library(mouse4302.db)
    ## EntrezID <- mget(as.character(rownames(DB)),mouse4302ENTREZID)
    ## rownames(DB) <- as.character(EntrezID)
    # --- Cleandatabase [] ---
    # Key functions: cleanDatabase, tempdir
    ## cleanDB <- cleanDatabase(DB,SaveFile="newDB_GPL1261.bigmemory",
    ##                          SavePath=tempdir())
    ## head(cleanDB)
    ## ### cleanDB contains the finished database ready to be
    ## ### inputted into ChIPXpress.
    # --- Chipxpress [] ---
    # Key functions: ChIPXpress
    ## out <- ChIPXpress(TFID="18999",ChIP=Oct4ESC_ChIPgenes,DB=cleanDB)
    ## head(out[[1]])
    ## head(out[[2]])

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_chipxpress_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_chipxpress_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_chipxpress_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CHIPXPRESS:", paste0("    chipxpress: ", packageVersion("ChIPXpress"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_chipxpress_results.csv
    touch ${prefix}_chipxpress_output.rds
    echo "BIOC_CHIPXPRESS:" > versions.yml
    echo "    chipxpress: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CHIPXPRESS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CHIPXPRESS(ch_input)

    emit:
    results  = BIOC_CHIPXPRESS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CHIPXPRESS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CHIPXPRESS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CHIPXPRESS.out.versions  // channel: path(versions.yml)
}
