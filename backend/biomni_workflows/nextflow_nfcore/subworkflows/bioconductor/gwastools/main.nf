#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GWASTools
// Classes for storing very large GWAS data sets and annotation, and functions for GWAS data cleaning a
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GWASTools/inst/doc/Affymetrix.R
// Upstream  : GWASdata, SNPRelate
// Downstream: mBPCR, GWASdata, snplinkage
//
// Install: BiocManager::install("GWASTools")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GWASTOOLS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-gwastools"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-gwastools:1.52.0--r44_0' :
        'quay.io/biocontainers/bioconductor-gwastools:1.52.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_gwastools_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_gwastools_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_gwastools_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BAFfromGenotypes)
    library(GdsGenotypeReader)
    library(GdsIntensityReader)
    library(GenotypeData)
    library(IntensityData)
    library(SNPs)
    library(ScanAnnotationDataFrame)
    library(jsonlite)

    # --- Annotation [] ---
    # Key functions: annotation, ScanAnnotationDataFrame, varLabels, pData, varMetadata
    ---------------------------------------------------------------------
    # Load the scan annotation (simple data frame)
    data(affy_scan_annot)
    # Create a ScanAnnotationDataFrame
    scanAnnot <- ScanAnnotationDataFrame(affy_scan_annot)
    # --- Intensitydata [] ---
    # Key functions: IntensityData, GdsIntensityReader, GenotypeData, GdsGenotypeReader, BAFfromGenotypes, close, created, SNPs
    ---------------------------------------------------------------------
    bl.file <- "tmp.bl.gds"
    xyData <- IntensityData(GdsIntensityReader(xy.file),
                            snpAnnot=snpAnnot)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_gwastools_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_gwastools_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_gwastools_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GWASTOOLS:", paste0("    gwastools: ", packageVersion("GWASTools"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gwastools_results.csv
    touch ${prefix}_gwastools_output.rds
    echo "BIOC_GWASTOOLS:" > versions.yml
    echo "    gwastools: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GWASTOOLS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GWASTOOLS(ch_input)

    emit:
    results  = BIOC_GWASTOOLS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GWASTOOLS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GWASTOOLS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GWASTOOLS.out.versions  // channel: path(versions.yml)
}
