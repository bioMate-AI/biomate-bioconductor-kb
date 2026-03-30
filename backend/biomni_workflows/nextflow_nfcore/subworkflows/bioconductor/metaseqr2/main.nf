#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: metaseqR2
// Provides an interface to several normalization and statistical testing packages for RNA-Seq gene exp
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/metaseqR2/inst/doc/metaseqr2-annotation.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("metaseqR2")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_METASEQR2 {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-metaseqr2"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-metaseqr2:1.18.1--r44_0' :
        'quay.io/biocontainers/bioconductor-metaseqr2:1.18.1--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_metaseqr2_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_metaseqr2_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_metaseqr2_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(metaseqR2)
    library(jsonlite)

    # --- ifelse [] ---
    # Key functions: ifelse, buildAnnotationDatabase
    library(metaseqR2)
    buildDir <- file.path(tempdir(),"test_anndb")
    dir.create(buildDir)
    # --- load Annotation [] ---
    # Key functions: loadAnnotation
    genes <- loadAnnotation(genome="mm10",refdb="ensembl",level="gene",type="gene",
    utrs <- loadAnnotation(genome="mm10",refdb="ensembl",level="gene",type="utr",
    sumEx <- loadAnnotation(genome="mm10",refdb="ensembl",level="gene",type="exon",
    # --- build Custom Annotation [] ---
    # Key functions: buildCustomAnnotation, loadAnnotation
    customDir <- file.path(tempdir(),"test_custom")
    dir.create(customDir)
    if (.Platform$OS.type == "unix" && !grepl("^darwin",R.version$os)) {
    # --- build Annotation Database [] ---
    # Key functions: buildAnnotationDatabase
    organisms <- list(
    sources <- c("ensembl","ucsc","refseq")
    buildAnnotationDatabase(organisms,sources,forceDownload=FALSE,rc=0.5)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_metaseqr2_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_metaseqr2_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_metaseqr2_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_METASEQR2:", paste0("    metaseqr2: ", packageVersion("metaseqR2"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_metaseqr2_results.csv
    touch ${prefix}_metaseqr2_output.rds
    echo "BIOC_METASEQR2:" > versions.yml
    echo "    metaseqr2: 0.0.0" >> versions.yml
    """
}


workflow BIOC_METASEQR2_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_METASEQR2(ch_input)

    emit:
    results  = BIOC_METASEQR2.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_METASEQR2.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_METASEQR2.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_METASEQR2.out.versions  // channel: path(versions.yml)
}
