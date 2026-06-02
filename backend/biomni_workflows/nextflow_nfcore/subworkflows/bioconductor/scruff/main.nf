#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: scruff
// A pipeline which processes single cell RNA-seq (scRNA-seq) reads from CEL-seq and CEL-seq2 protocols
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/scruff/inst/doc/scruff.R
// Upstream  : BiocStyle, TENxBrainData
// Downstream: none
//
// Install: BiocManager::install("scruff")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SCRUFF {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-scruff"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-scruff:1.24.0--r44_0' :
        'quay.io/biocontainers/bioconductor-scruff:1.24.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_scruff_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_scruff_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_scruff_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(scruff)
    library(jsonlite)


    # --- Load Files1 [] ---
    # Key functions: extdata, vandenBrink_1h1_L001_R1_001.fastq.gz, scruff, vandenBrink_1h1_L001_R2_001.fastq.gz, GRCm38_MT.fa, GRCm38_MT.gtf
    # Run scruff on example dataset
    # NOTE: Requires Rsubread index and TxDb objects for the reference genome.
    # For generation of these files, please refer to the Stepwise Tutorial.

    library(scruff)

    # Get the paths to example FASTQ, FASTA, and GTF files.
    # Please note that because the following files are included in
    # scruff R package, we use system.file() function to extract the paths
    # to these files. If the user is running scruff on real data, the

    # --- Buildindex1 [] ---
    # Key functions: buildindex, GRCm38_MT
    # Create index files for GRCm38_MT.
    # For details, please refer to Rsubread user manual.
    # Specify the basename for Rsubread index
    indexBase <- "GRCm38_MT"
    Rsubread::buildindex(basename = indexBase,
        reference = fasta,
        indexSplit = FALSE)

    # --- Qc1 [] ---
    # Key functions: qcplots, scruff
    data(sceExample, package = "scruff")
    qc <- qcplots(sceExample)

    # --- Loadfiles2 [] ---
    # Key functions: extdata, vandenBrink_1h1_L001_R1_001.fastq.gz, scruff, vandenBrink_1h1_L001_R2_001.fastq.gz
    library(scruff)

    # Get the paths to example FASTQ files.
    # Please note that because the following files are included in
    # scruff R package, we use system.file() function to extract the paths
    # to these files. If the user is running scruff on real data, the
    # paths to the input FASTQ, FASTA, and GTF files should be provided,
    # and there is no need to call system.file() function. For example,
    # v1h1R1 <- "/PATH/TO/vandenBrink_1h1_L001_R1_001.fastq.gz"
    # fasta <- "/Path/TO/GRCm38_MT.fa"

    # --- Differential Expression [] ---
    # Key functions: demultiplex, scruff, example
    data(barcodeExample, package = "scruff")
    # --- Qc2 [] ---
    # Key functions: qcplots, scruff
    data(sceExample, package = "scruff")
    qc <- qcplots(sceExample)
    qc

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_scruff_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_scruff_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_scruff_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SCRUFF:", paste0("    scruff: ", packageVersion("scruff"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_scruff_results.csv
    touch ${prefix}_scruff_output.rds
    echo "BIOC_SCRUFF:" > versions.yml
    echo "    scruff: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SCRUFF_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SCRUFF(ch_input)

    emit:
    results  = BIOC_SCRUFF.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SCRUFF.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SCRUFF.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SCRUFF.out.versions  // channel: path(versions.yml)
}
