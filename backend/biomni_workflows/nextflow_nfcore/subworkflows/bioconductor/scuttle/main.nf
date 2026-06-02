#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: scuttle
// Provides basic utility functions for performing single-cell analyses, focusing on simple normalizati
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/scuttle/inst/doc/misc.R
// Upstream  : BiocStyle, scRNAseq, scran
// Downstream: scater, scran, OSCA.advanced, OSCA.basic, OSCA.intro
//
// Install: BiocManager::install("scuttle")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SCUTTLE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-scuttle"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-scuttle:1.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-scuttle:1.16.0--r44_0'}"

    input:
    tuple val(meta), path(seurat_object)

    output:
    tuple val(meta), path("${meta.id}_scuttle_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_scuttle_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_scuttle_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ZeiselBrainData)
    library(jsonlite)

    # --- Zeiselbraindata [] ---
    # Key functions: ZeiselBrainData, quickPerCellQC
    ---------------------------------------------------------------------
    library(scRNAseq)
    sce <- ZeiselBrainData()
    library(scuttle)
    # --- Aggregateacrosscells [] ---
    # Key functions: aggregateAcrossCells, assay, colData
    ---------------------------------------------------------------------
    library(scuttle)
    agg.sce <- aggregateAcrossCells(sce, ids=sce$level1class)
    head(assay(agg.sce))
    colData(agg.sce)[,c("ids", "ncells")]
    # --- Lognormcounts [] ---
    # Key functions: logNormCounts, sumCountsAcrossFeatures
    ---------------------------------------------------------------------
    sce <- logNormCounts(sce)
    agg.feat <- sumCountsAcrossFeatures(sce,
        ids=list(GeneSet1=1:10, GeneSet2=11:50, GeneSet3=1:100),
        average=TRUE, exprs_values="logcounts")
    # --- Summarizeassaybygroup [] ---
    # Key functions: summarizeAssayByGroup, colData, assay
    ---------------------------------------------------------------------
    agg.n <- summarizeAssayByGroup(sce, statistics="prop.detected",
        ids=colData(sce)[,c("level1class", "tissue")])
    head(assay(agg.n))
    # --- Zeiselbraindata [] ---
    # Key functions: ZeiselBrainData, uniquifyFeatureNames, rowData
    ---------------------------------------------------------------------
    # Original row names are Ensembl IDs.
    sce.ens <- ZeiselBrainData(ensembl=TRUE)
    head(rownames(sce.ens))
    # Replacing with guaranteed unique and non-missing symbols:
    # --- Makepercelldf [] ---
    # Key functions: makePerCellDF
    ---------------------------------------------------------------------
    out <- makePerCellDF(sce, features="Tspan12")
    colnames(out)
    # --- Makeperfeaturedf [] ---
    # Key functions: makePerFeatureDF
    ---------------------------------------------------------------------
    out2 <- makePerFeatureDF(sce, cells=c("1772063062_D05",
        "1772063061_D01", "1772060240_F02", "1772062114_F05"))
    colnames(out2)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_scuttle_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_scuttle_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_scuttle_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SCUTTLE:", paste0("    scuttle: ", packageVersion("scuttle"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_scuttle_results.csv
    touch ${prefix}_scuttle_output.rds
    echo "BIOC_SCUTTLE:" > versions.yml
    echo "    scuttle: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SCUTTLE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(seurat_object) ]

    main:
    BIOC_SCUTTLE(ch_input)

    emit:
    results  = BIOC_SCUTTLE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SCUTTLE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SCUTTLE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SCUTTLE.out.versions  // channel: path(versions.yml)
}
