#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: scTensor
// The algorithm is based on the non-negative tucker decomposition (NTD2) of nnTensor.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/scTensor/inst/doc/scTensor.R
// Upstream  : AnnotationHub, LRBaseDbi, RSQLite, Seurat, SingleCellExperiment
// Downstream: none
//
// Install: BiocManager::install("scTensor")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SCTENSOR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-sctensor"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-sctensor:2.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-sctensor:2.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_sctensor_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_sctensor_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_sctensor_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(AnnotationHub)
    library(SingleCellExperiment)
    library(jsonlite)

    # --- Access AnnotationHub resources [] ---
    # Key functions: AnnotationHub, mcols
    library("AnnotationHub")
    ah <- AnnotationHub()
    mcols(ah)
    # --- query [] ---
    # Key functions: query
    dbfile <- query(ah, c("LRBaseDb", "Homo sapiens", "v002"))[[1]]
    # --- Access [] ---
    # Key functions: columns, keytypes, keys
    columns(LRBase.Hsa.eg.db)
    keytypes(LRBase.Hsa.eg.db)
    key_HSA <- keys(LRBase.Hsa.eg.db, keytype="GENEID_L")
    # --- Other1 [] ---
    # Key functions: lrNomenclature, species, lrListDatabases, lrVersion, dbInfo
    lrNomenclature(LRBase.Hsa.eg.db)
    species(LRBase.Hsa.eg.db)
    lrListDatabases(LRBase.Hsa.eg.db)
    # --- Other2 [] ---
    # Key functions: dbGetQuery
    suppressPackageStartupMessages(library("RSQLite"))
    dbGetQuery(dbconn(LRBase.Hsa.eg.db),
    # --- Create SingleCellExperiment object [] ---
    # Key functions: SingleCellExperiment, reducedDims
    data(GermMale)
    data(labelGermMale)
    data(tsneGermMale)
    # --- cell Cell Setting [] ---
    # Key functions: cellCellSetting
    cellCellSetting(sce, LRBase.Hsa.eg.db, names(labelGermMale))
    # --- cell Cell Decomp [] ---
    # Key functions: cellCellDecomp
    set.seed(1234)
    cellCellDecomp(sce, ranks=c(2,3))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_sctensor_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_sctensor_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_sctensor_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SCTENSOR:", paste0("    sctensor: ", packageVersion("scTensor"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sctensor_results.csv
    touch ${prefix}_sctensor_output.rds
    echo "BIOC_SCTENSOR:" > versions.yml
    echo "    sctensor: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SCTENSOR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SCTENSOR(ch_input)

    emit:
    results  = BIOC_SCTENSOR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SCTENSOR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SCTENSOR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SCTENSOR.out.versions  // channel: path(versions.yml)
}
