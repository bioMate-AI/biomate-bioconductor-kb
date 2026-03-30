#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: scCB2
// scCB2 is an R package implementing CB2 for distinguishing real cells from empty droplets in droplet-
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/scCB2/inst/doc/scCB2.R
// Upstream  : SummarizedExperiment, knitr
// Downstream: none
//
// Install: BiocManager::install("scCB2")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SCCB2 {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-sccb2"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-sccb2:1.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-sccb2:1.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_sccb2_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_sccb2_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_sccb2_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CB2FindCell)
    library(CheckBackgroundCutoff)
    library(CreateSeuratObject)
    library(GetCellMat)
    library(QuickCB2)
    library(Read10xRaw)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: path, tempdir, write10xCounts, files
    ---------------------------------------------------------------------
    library(scCB2)
    library(SummarizedExperiment)
    data(mbrainSub)
    data.dir <- file.path(tempdir(),"CB2_example")
    # --- Read10x Raw [] ---
    # Key functions: Read10xRaw
    ---------------------------------------------------------------------
    mbrainSub_2 <- Read10xRaw(data.dir)
    identical(mbrainSub, mbrainSub_2)
    # --- Checkbackgroundcutoff [] ---
    # Key functions: CheckBackgroundCutoff
    ---------------------------------------------------------------------
    check_cutoff <- CheckBackgroundCutoff(mbrainSub)
    check_cutoff$summary_table
    check_cutoff$recommended_cutoff
    # --- C B2 Find Cell [] ---
    # Key functions: CB2FindCell, assay, metadata
    ---------------------------------------------------------------------
    CBOut <- CB2FindCell(mbrainSub, FDR_threshold = 0.01, lower = 100, Ncores = 2)
    str(assay(CBOut)) # cell matrix
    str(metadata(CBOut)) # test statistics, p-values, etc
    # --- Getcellmat [] ---
    # Key functions: GetCellMat
    ---------------------------------------------------------------------
    RealCell <- GetCellMat(CBOut, MTfilter = 0.25)
    str(RealCell)
    # --- Createseuratobject [] ---
    # Key functions: CreateSeuratObject
    ---------------------------------------------------------------------
    SeuratObj <- Seurat::CreateSeuratObject(counts = RealCell,
                                            project = "mbrain_example")
    SeuratObj
    # --- Quickcb2 [] ---
    # Key functions: QuickCB2
    ---------------------------------------------------------------------
    RealCell_Quick <- QuickCB2(dir = data.dir, Ncores = 2)
    str(RealCell_Quick)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_sccb2_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_sccb2_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_sccb2_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SCCB2:", paste0("    sccb2: ", packageVersion("scCB2"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sccb2_results.csv
    touch ${prefix}_sccb2_output.rds
    echo "BIOC_SCCB2:" > versions.yml
    echo "    sccb2: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SCCB2_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SCCB2(ch_input)

    emit:
    results  = BIOC_SCCB2.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SCCB2.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SCCB2.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SCCB2.out.versions  // channel: path(versions.yml)
}
