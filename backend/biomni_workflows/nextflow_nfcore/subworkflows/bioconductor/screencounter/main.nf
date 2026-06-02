#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: screenCounter
// Provides functions for counting reads from high-throughput sequencing screen data (e.g., CRISPR, shR
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/screenCounter/inst/doc/counting.R
// Upstream  : BiocParallel, BiocStyle, Biostrings
// Downstream: none
//
// Install: BiocManager::install("screenCounter")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SCREENCOUNTER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-screencounter"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-screencounter:1.6.0--r44_0' :
        'quay.io/biocontainers/bioconductor-screencounter:1.6.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_screencounter_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_screencounter_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_screencounter_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DataFrame)
    library(jsonlite)

    # --- Matrixofsinglebarcodes [] ---
    # Key functions: matrixOfSingleBarcodes, assay
    ---------------------------------------------------------------------
    library(screenCounter)
    out <- matrixOfSingleBarcodes(single.fq,
        flank5="GTAC", flank3="CATG", choices=known)
    out
    # --- Matrixofcombobarcodes [] ---
    # Key functions: matrixOfComboBarcodes
    ---------------------------------------------------------------------
    out <- matrixOfComboBarcodes(combo.fq,
        template="GTACNNNNCATGNNNNGTAC",
        choices=list(first=known1, second=known2))
    out
    # --- Assay [] ---
    # Key functions: assay
    ---------------------------------------------------------------------
    assay(out)
    # --- Rowdata [] ---
    # Key functions: rowData
    ---------------------------------------------------------------------
    rowData(out)
    # --- Grid [] ---
    # Key functions: grid, DataFrame, sample
    ---------------------------------------------------------------------
    choices <- expand.grid(known.pool1, known.pool2)
    choices <- DataFrame(barcode1=choices[,1], barcode2=choices[,2])
    choices <- choices[sample(nrow(choices), nrow(choices)*0.9),]
    # --- Matrixofdualbarcodes [] ---
    # Key functions: matrixOfDualBarcodes
    ---------------------------------------------------------------------
    out <- matrixOfDualBarcodes(list(c(tmp1, tmp2)),
        choices=choices,
        template=c("CAGCTACGTACGNNNNNNNNNCCAGCTCGATCG",
                   "TGGGCAGCGACANNNNNNNNNACACGAGGGTAT"))
    # --- Assay [] ---
    # Key functions: assay
    ---------------------------------------------------------------------
    assay(out)
    # --- Coldata [] ---
    # Key functions: colData
    ---------------------------------------------------------------------
    colData(out)
    # --- Rowdata [] ---
    # Key functions: rowData
    ---------------------------------------------------------------------
    rowData(out)
    # --- Grid [] ---
    # Key functions: grid, DataFrame, sample
    ---------------------------------------------------------------------
    choices <- expand.grid(known.pool1, known.pool2)
    choices <- DataFrame(barcode1=choices[,1], barcode2=choices[,2])
    choices <- choices[sample(nrow(choices), nrow(choices)*0.9),]
    # --- Matrixofdualbarcodessingleend [] ---
    # Key functions: matrixOfDualBarcodesSingleEnd
    ---------------------------------------------------------------------
    out <- matrixOfDualBarcodesSingleEnd(tmp, choices=choices,
        template="CAGCTACGTACGNNNNNNNNNCCAGCTCGATCGNNNNNNNNNACACGAGGGTAT")
    out
    # --- Assay [] ---
    # Key functions: assay
    ---------------------------------------------------------------------
    assay(out)
    # --- Coldata [] ---
    # Key functions: colData
    ---------------------------------------------------------------------
    colData(out)
    # --- Rowdata [] ---
    # Key functions: rowData
    ---------------------------------------------------------------------
    rowData(out)
    # --- Lapply [] ---
    # Key functions: sample
    ---------------------------------------------------------------------
    # Mocking up a 8-bp random variable region.
    N <- 1000

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_screencounter_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_screencounter_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_screencounter_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SCREENCOUNTER:", paste0("    screencounter: ", packageVersion("screenCounter"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_screencounter_results.csv
    touch ${prefix}_screencounter_output.rds
    echo "BIOC_SCREENCOUNTER:" > versions.yml
    echo "    screencounter: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SCREENCOUNTER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SCREENCOUNTER(ch_input)

    emit:
    results  = BIOC_SCREENCOUNTER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SCREENCOUNTER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SCREENCOUNTER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SCREENCOUNTER.out.versions  // channel: path(versions.yml)
}
