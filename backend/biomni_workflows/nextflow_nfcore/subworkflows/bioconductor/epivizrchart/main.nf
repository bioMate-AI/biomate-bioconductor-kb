#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: epivizrChart
// This package provides an API for interactive visualization of genomic data using epiviz web componen
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/epivizrChart/inst/doc/IntegrationWithIGVjs.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("epivizrChart")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_EPIVIZRCHART {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-epivizrchart"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-epivizrchart:1.28.0--r44_0' :
        'quay.io/biocontainers/bioconductor-epivizrchart:1.28.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_epivizrchart_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_epivizrchart_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_epivizrchart_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BEDFile)
    library(BamFile)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    data(tcga_colon_blocks)
    # --- Epivizenv [] ---
    # Key functions: epivizEnv
    ---------------------------------------------------------------------
    epiviz_env <- epivizEnv(chr="chr11", start=118000000, end=121000000)
    genes_track <- epiviz_env$plot(Homo.sapiens)
    blocks_track <- epiviz_env$plot(tcga_colon_blocks, datasource_name="450kMeth")
    # --- Bamfile [] ---
    # Key functions: BamFile, BEDFile
    ---------------------------------------------------------------------
    file1 <- Rsamtools::BamFile("http://1000genomes.s3.amazonaws.com/phase3/data/HG01879/alignment/HG01879.mapped.ILLUMINA.bwa.ACB.low_coverage.20120522.bam")
    file2 <- rtracklayer::BEDFile("https://s3.amazonaws.com/igv.broadinstitute.org/annotations/hg19/genes/refGene.hg19.bed.gz")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_epivizrchart_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_epivizrchart_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_epivizrchart_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_EPIVIZRCHART:", paste0("    epivizrchart: ", packageVersion("epivizrChart"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_epivizrchart_results.csv
    touch ${prefix}_epivizrchart_output.rds
    echo "BIOC_EPIVIZRCHART:" > versions.yml
    echo "    epivizrchart: 0.0.0" >> versions.yml
    """
}


workflow BIOC_EPIVIZRCHART_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_EPIVIZRCHART(ch_input)

    emit:
    results  = BIOC_EPIVIZRCHART.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_EPIVIZRCHART.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_EPIVIZRCHART.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_EPIVIZRCHART.out.versions  // channel: path(versions.yml)
}
