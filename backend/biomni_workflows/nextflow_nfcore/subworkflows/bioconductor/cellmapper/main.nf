#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: CellMapper
// Infers cell type-specific expression based on co-expression similarity with known cell type marker g
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/CellMapper/inst/doc/CellMapper.R
// Upstream  : ALL, ExperimentHub
// Downstream: CellMapperData
//
// Install: BiocManager::install("CellMapper")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CELLMAPPER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cellmapper"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cellmapper:1.32.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cellmapper:1.32.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cellmapper_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cellmapper_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cellmapper_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CMprep)
    library(CMsearch)
    library(ExperimentHub)
    library(jsonlite)

    # --- Experimenthub [] ---
    # Key functions: ExperimentHub, query
    library("ExperimentHub")
    hub <- ExperimentHub()
    x <- query(hub, "CellMapperData")
    x
    # --- Cmsearch [] ---
    # Key functions: CMsearch
    GABAergic <- CMsearch(BrainAtlas, query.genes = query)
    # --- Csv [] ---
    # Key functions: csv
    ## write.csv(GABAergic, file = "CellMapper analysis for GABAergic neurons.csv")
    # --- Cmsearch [] ---
    # Key functions: CMsearch
    query2 <- "3856"
    SimpleEpithelia <- CMsearch(list(Engreitz, Lukk, ZhengBradley), query.genes =
    query2)
    head(SimpleEpithelia)
    # --- Data [] ---
    # Key functions: data
    library(ALL)
    data(ALL)
    # --- Cmprep [] ---
    # Key functions: CMprep
    prepped.data <- CMprep(ALL)
    # --- Cmsearch [] ---
    # Key functions: CMsearch
    out <- CMsearch(prepped.data, query.genes = "1000_at")
    head(out)
    # --- Query [] ---
    # Key functions: query
    query(hub, "HumanAffyData")
    # --- Pdata [] ---
    # Key functions: pData
    pDat <- pData(E.MTAB.62)
    # --- Exprs [] ---
    # Key functions: exprs
    Lukk_unprocessed.gut <- exprs(E.MTAB.62)[, samples]
    # --- Cmprep [] ---
    # Key functions: CMprep
    Lukk.gut <- CMprep(Lukk_unprocessed.gut)
    # --- Pdata [] ---
    # Key functions: pData
    GSE64985 <- hub[["EH176"]]
    pDat <- pData(GSE64985)
    # --- Exprs [] ---
    # Key functions: exprs
    Engreitz_unprocessed.gut = exprs(GSE64985)[,select]
    # --- Cmprep [] ---
    # Key functions: CMprep
    Engreitz.gut = CMprep(Engreitz_unprocessed.gut)
    # --- Cmsearch [] ---
    # Key functions: CMsearch
    query = "1113"
    EECs <- CMsearch(list(Lukk = Lukk.gut, Engreitz = Engreitz.gut), query.genes =
    	query)
    head(EECs)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cellmapper_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cellmapper_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cellmapper_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CELLMAPPER:", paste0("    cellmapper: ", packageVersion("CellMapper"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cellmapper_results.csv
    touch ${prefix}_cellmapper_output.rds
    echo "BIOC_CELLMAPPER:" > versions.yml
    echo "    cellmapper: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CELLMAPPER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CELLMAPPER(ch_input)

    emit:
    results  = BIOC_CELLMAPPER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CELLMAPPER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CELLMAPPER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CELLMAPPER.out.versions  // channel: path(versions.yml)
}
