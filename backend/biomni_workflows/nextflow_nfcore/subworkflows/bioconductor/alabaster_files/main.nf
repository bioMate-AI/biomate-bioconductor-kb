#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: alabaster.files
// Save common bioinformatics file formats within the alabaster framework. This includes BAM, BED, VCF,
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/alabaster.files/inst/doc/userguide.R
// Upstream  : BiocStyle, S4Vectors
// Downstream: none
//
// Install: BiocManager::install("alabaster.files")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ALABASTER_FILES {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-alabaster_files"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-alabaster.files:1.4.0--r44_0' :
        'quay.io/biocontainers/bioconductor-alabaster.files:1.4.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_alabaster_files_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_alabaster_files_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_alabaster_files_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BamFileReference)
    library(BcfFileReference)
    library(BigBedFileReference)
    library(BigWigFileReference)
    library(DataFrame)
    library(jsonlite)

    # --- Bamfilereference [] ---
    # Key functions: BamFileReference
    ---------------------------------------------------------------------
    library(alabaster.files)
    library(S4Vectors)
    wrapped.bam <- BamFileReference(bam.file, index=bam.index)
    # --- Readobject [] ---
    # Key functions: readObject
    ---------------------------------------------------------------------
    readObject(dir)
    # --- Dataframe [] ---
    # Key functions: DataFrame, BigWigFileReference, BigBedFileReference, BcfFileReference, tempfile, saveObject
    ---------------------------------------------------------------------
    df <- DataFrame(Sample=LETTERS[1:4])
    # Adding a column of assorted wrapper files:
    df$File <- list(
        wrapped.bam,

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_alabaster_files_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_alabaster_files_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_alabaster_files_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ALABASTER_FILES:", paste0("    alabaster_files: ", packageVersion("alabaster.files"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_alabaster_files_results.csv
    touch ${prefix}_alabaster_files_output.rds
    echo "BIOC_ALABASTER_FILES:" > versions.yml
    echo "    alabaster_files: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ALABASTER_FILES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ALABASTER_FILES(ch_input)

    emit:
    results  = BIOC_ALABASTER_FILES.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ALABASTER_FILES.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ALABASTER_FILES.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ALABASTER_FILES.out.versions  // channel: path(versions.yml)
}
