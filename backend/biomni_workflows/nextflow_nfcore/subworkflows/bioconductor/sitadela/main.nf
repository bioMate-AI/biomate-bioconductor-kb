#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: sitadela
// Provides an interface to build a unified database of genomic annotations and their coordinates (gene
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/sitadela/inst/doc/sitadela.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("sitadela")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SITADELA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-sitadela"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-sitadela:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-sitadela:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_sitadela_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_sitadela_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_sitadela_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(sitadela)
    library(jsonlite)

    # --- ifelse [] ---
    # Key functions: ifelse, addAnnotation, setDbPath
    library(sitadela)
    buildDir <- file.path(tempdir(),"test_anndb")
    dir.create(buildDir)
    # --- load Annotation [] ---
    # Key functions: loadAnnotation
    genes <- loadAnnotation(genome="mm10",refdb="ensembl",type="gene",db=myDb)
    utrs <- loadAnnotation(genome="mm10",refdb="ensembl",type="utr",db=myDb)
    sumEx <- loadAnnotation(genome="mm10",refdb="ensembl",type="exon",
    # --- tempfile [] ---
    # Key functions: tempfile, addCustomAnnotation, loadAnnotation, unlink
    gtf <- system.file(package="sitadela","extdata",
    chrom <- system.file(package="sitadela","extdata",
    chromInfo <- read.delim(chrom,header=FALSE,row.names=1)
    # --- add Custom Annotation [] ---
    # Key functions: addCustomAnnotation, loadAnnotation
    customDir <- file.path(tempdir(),"test_custom")
    dir.create(customDir)
    if (.Platform$OS.type == "unix" && !grepl("^darwin",R.version$os)) {
    # --- add Annotation [] ---
    # Key functions: addAnnotation
    organisms <- list(
    sources <- c("ensembl","ucsc","refseq","ncbi")
    addAnnotation(organisms,sources,forceDownload=FALSE,rc=0.5)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_sitadela_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_sitadela_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_sitadela_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SITADELA:", paste0("    sitadela: ", packageVersion("sitadela"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sitadela_results.csv
    touch ${prefix}_sitadela_output.rds
    echo "BIOC_SITADELA:" > versions.yml
    echo "    sitadela: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SITADELA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SITADELA(ch_input)

    emit:
    results  = BIOC_SITADELA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SITADELA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SITADELA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SITADELA.out.versions  // channel: path(versions.yml)
}
