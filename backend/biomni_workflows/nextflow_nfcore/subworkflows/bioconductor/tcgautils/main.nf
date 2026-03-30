#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: TCGAutils
// A suite of helper functions for checking and manipulating TCGA data including data obtained from the
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/TCGAutils/inst/doc/TCGAutils.R
// Upstream  : AnnotationHub, BiocStyle, MultiAssayExperiment, RTCGAToolbox, curatedTCGAData
// Downstream: none
//
// Install: BiocManager::install("TCGAutils")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TCGAUTILS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-tcgautils"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-tcgautils:1.26.0--r44_0' :
        'quay.io/biocontainers/bioconductor-tcgautils:1.26.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_tcgautils_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_tcgautils_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_tcgautils_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CpGtoRanges)
    library(DataFrame)
    library(TCGAbarcode)
    library(TCGAbiospec)
    library(TCGAprimaryTumors)
    library(TCGAsampleSelect)
    library(TCGAsplitAssays)
    library(UUIDhistory)
    library(UUIDtoBarcode)
    library(UUIDtoUUID)
    library(jsonlite)

    # --- Curatedtcgadata [] ---
    # Key functions: curatedTCGAData
    ---------------------------------------------------------------------
    curatedTCGAData("COAD", "*", dry.run = TRUE, version = "1.1.38")
    # --- Sampletables [] ---
    # Key functions: sampleTables
    ---------------------------------------------------------------------
    sampleTables(coad)
    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    data("sampleTypes")
    head(sampleTypes)
    # --- Tcgasplitassays [] ---
    # Key functions: TCGAsplitAssays
    ---------------------------------------------------------------------
    (tnmae <- TCGAsplitAssays(coad, c("01", "11")))
    # --- Getsubtypemap [] ---
    # Key functions: getSubtypeMap
    ---------------------------------------------------------------------
    getSubtypeMap(coad)
    # --- Getclinicalnames [] ---
    # Key functions: getClinicalNames
    ---------------------------------------------------------------------
    getClinicalNames("COAD")
    # --- Class [] ---
    # Key functions: colData
    ---------------------------------------------------------------------
    class(colData(coad)[["vital_status.x"]])
    class(colData(coad)[["vital_status.y"]])
    table(colData(coad)[["vital_status.x"]])
    table(colData(coad)[["vital_status.y"]])
    # --- Cpgtoranges [] ---
    # Key functions: CpGtoRanges
    ---------------------------------------------------------------------
    methcoad <- CpGtoRanges(coad)
    # --- Mirtoranges [] ---
    # Key functions: mirToRanges
    ---------------------------------------------------------------------
    mircoad <- mirToRanges(coad)
    # --- Genome [] ---
    # Key functions: genome, seqlevelsStyle, rowRanges, seqlevels
    ---------------------------------------------------------------------
    rag <- "COAD_Mutation-20160128"
    # add the appropriate genome annotation
    genome(coad[[rag]]) <- "NCBI36"
    # change the style to UCSC
    # --- Query [] ---
    # Key functions: query, liftOver, rowRanges
    ---------------------------------------------------------------------
    query(ah, "hg18ToHg19.over.chain.gz")
    chain <- ah[["AH14220"]]
    ranges19 <- rtracklayer::liftOver(rowRanges(coad[[rag]]), chain)
    # --- Logical [] ---
    # Key functions: lengths, unlist, genome, rowRanges
    ---------------------------------------------------------------------
    re19 <- coad[[rag]][as.logical(lengths(ranges19))]
    ranges19 <- unlist(ranges19)
    genome(ranges19) <- "hg19"
    rowRanges(re19) <- ranges19
    # --- Qreducetcga [] ---
    # Key functions: qreduceTCGA
    ---------------------------------------------------------------------
    coad <- qreduceTCGA(coad, keep.assay = TRUE)
    # --- Symbolstoranges [] ---
    # Key functions: symbolsToRanges
    ---------------------------------------------------------------------
    symbolsToRanges(coad)
    # --- Dataframe [] ---
    # Key functions: DataFrame, factor, colData, mergeColData
    ---------------------------------------------------------------------
    race_df <- DataFrame(race_f = factor(colData(coad)[["race"]]),
        row.names = rownames(colData(coad)))
    mergeColData(coad, race_df)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_tcgautils_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_tcgautils_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_tcgautils_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TCGAUTILS:", paste0("    tcgautils: ", packageVersion("TCGAutils"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tcgautils_results.csv
    touch ${prefix}_tcgautils_output.rds
    echo "BIOC_TCGAUTILS:" > versions.yml
    echo "    tcgautils: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TCGAUTILS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TCGAUTILS(ch_input)

    emit:
    results  = BIOC_TCGAUTILS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TCGAUTILS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TCGAUTILS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TCGAUTILS.out.versions  // channel: path(versions.yml)
}
