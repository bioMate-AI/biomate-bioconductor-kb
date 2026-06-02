#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: VariantExperiment
// VariantExperiment is a Bioconductor package for saving data in VCF/GDS format into RangedSummarizedE
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/VariantExperiment/inst/doc/VariantExperiment-class.R
// Upstream  : GDSArray
// Downstream: none
//
// Install: BiocManager::install("VariantExperiment")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_VARIANTEXPERIMENT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-variantexperiment"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-variantexperiment:1.20.0--r44_0' :
        'quay.io/biocontainers/bioconductor-variantexperiment:1.20.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_variantexperiment_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_variantexperiment_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_variantexperiment_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(VariantExperiment)
    library(jsonlite)


    # --- Gdsarray [] ---
    # Key functions: gdsExampleFileName, gdsnodes, GDSArray, seqgds, sample.id, makeVariantExperimentFromGDS, args, showAvailable
    library(GDSArray)
    file <- GDSArray::gdsExampleFileName("seqgds")
    gdsnodes(file)
    GDSArray(file, "genotype/data")
    GDSArray(file, "sample.id")
    ve <- makeVariantExperimentFromGDS(file)
    ve
    args(makeVariantExperimentFromGDS)
    showAvailable(file)
    assays(ve)
    assay(ve, 1)
    GDSArray(file, "genotype/data")  ## original GDSArray from GDS file before permutation

    # --- Rrrd [] ---
    # Key functions: rowRanges, rowData, colData, gdsfile, metadata
    rowRanges(ve)
    rowData(ve)
    colData(ve)
    gdsfile(ve)
    metadata(ve)

    # --- Make Variant Experiment From Vcf [] ---
    # Key functions: seqExampleFileName, makeVariantExperimentFromVCF, tempfile, vcf, gdsfile, assay, rowData
    vcf <- SeqArray::seqExampleFileName("vcf")
    ve <- makeVariantExperimentFromVCF(vcf, out.dir = tempfile())
    ve
    gdsfile(ve)
    assay(ve, 1)
    rowData(ve)

    # --- Sample Info [] ---
    # Key functions: makeVariantExperimentFromVCF, colData, extdata, Example_sampleInfo.txt, rowData, seqExampleFileName, makeVariantExperimentFromGDS, gds
    sampleInfo <- system.file("extdata", "Example_sampleInfo.txt",
                              package="VariantExperiment")
    vevcf <- makeVariantExperimentFromVCF(vcf, sample.info = sampleInfo)
    colData(vevcf)
    vevcf1 <- makeVariantExperimentFromVCF(vcf, info.import=c("OR", "GP"))
    rowData(vevcf1)
    vevcf2 <- makeVariantExperimentFromVCF(vcf, start=101, count=1000)
    vevcf2
    gds <- SeqArray::seqExampleFileName("gds")
    ve <- makeVariantExperimentFromGDS(gds)
    ve

    # --- Show Available1 [] ---
    # Key functions: showAvailable, makeVariantExperimentFromGDS, rowData, colData, character, allele, snpgdsExampleFileName, snp.allele
    showAvailable(gds)
    ve3 <- makeVariantExperimentFromGDS(gds,
                                        rowDataColumns = c("allele", "annotation/id"),
                                        infoColumns = c("AC", "AN", "DP"),
                                        rowDataOnDisk = TRUE,
                                        colDataOnDisk = FALSE)
    rowData(ve3)  ## DelayedDataFrame object 
    colData(ve3)  ## DataFrame object

    ## -----------------------------------------------------------------------------
    # --- Col Data Extraction [] ---
    # Key functions: colData, rowData, subsetByOverlaps, GRanges, tempfile, saveVariantExperiment
    colData(ve)
    ve[, as.logical(ve$family == "1328")]
    rowData(ve)
    ve[as.logical(rowData(ve)$REF == "T"),]
    ve1 <- subsetByOverlaps(ve, GRanges("22:1-48958933"))
    ve1
    a <- tempfile()
    ve2 <- saveVariantExperiment(ve1, dir=a, replace=TRUE, chunk_size = 30)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_variantexperiment_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_variantexperiment_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_variantexperiment_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_VARIANTEXPERIMENT:", paste0("    variantexperiment: ", packageVersion("VariantExperiment"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_variantexperiment_results.csv
    touch ${prefix}_variantexperiment_output.rds
    echo "BIOC_VARIANTEXPERIMENT:" > versions.yml
    echo "    variantexperiment: 0.0.0" >> versions.yml
    """
}


workflow BIOC_VARIANTEXPERIMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_VARIANTEXPERIMENT(ch_input)

    emit:
    results  = BIOC_VARIANTEXPERIMENT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_VARIANTEXPERIMENT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_VARIANTEXPERIMENT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_VARIANTEXPERIMENT.out.versions  // channel: path(versions.yml)
}
