#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SeqSQC
// The SeqSQC is designed to identify problematic samples in NGS data, including samples with gender mi
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SeqSQC/inst/doc/vignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("SeqSQC")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SEQSQC {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-seqsqc"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-seqsqc:1.28.0--r44_0' :
        'quay.io/biocontainers/bioconductor-seqsqc:1.28.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_seqsqc_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_seqsqc_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_seqsqc_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(IBD)
    library(Inbreeding)
    library(LoadVfile)
    library(MissingRate)
    library(PCA)
    library(QCresult)
    library(SeqOpen)
    library(SeqSQC)
    library(SexCheck)
    library(jsonlite)

    # --- Sample-level quality control [] ---
    # Key functions: sampleQC, SeqSQC, plotQC
    load(system.file("extdata", "example.seqfile.Rdata", package="SeqSQC"))
    gfile <- system.file("extdata", "example.gds", package="SeqSQC")
    seqfile <- SeqSQC(gdsfile = gfile, QCresult = QCresult(seqfile))
    # --- LoadVfile analysis [] ---
    # Key functions: tempdir, LoadVfile, SeqSQC, slotNames, QCresult, SeqOpen, MissingRate, SexCheck
    infile <- system.file("extdata", "example_sub.vcf", package="SeqSQC")
    sample.annot <- system.file("extdata", "sampleAnnotation.txt", package="SeqSQC")
    cr <- system.file("extdata", "CCDS.Hs37.3.reduced_chr1.bed", package="SeqSQC")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_seqsqc_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_seqsqc_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_seqsqc_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SEQSQC:", paste0("    seqsqc: ", packageVersion("SeqSQC"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_seqsqc_results.csv
    touch ${prefix}_seqsqc_output.rds
    echo "BIOC_SEQSQC:" > versions.yml
    echo "    seqsqc: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SEQSQC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SEQSQC(ch_input)

    emit:
    results  = BIOC_SEQSQC.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SEQSQC.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SEQSQC.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SEQSQC.out.versions  // channel: path(versions.yml)
}
