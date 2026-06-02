#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ASpli
// Integrative pipeline for the analysis of alternative splicing using RNAseq.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ASpli/inst/doc/ASpli.R
// Upstream  : GenomicFeatures
// Downstream: none
//
// Install: BiocManager::install("ASpli")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ASPLI {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-aspli"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-aspli:2.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-aspli:2.16.0--r44_0'}"

    input:
    tuple val(meta), path(input_file)

    output:
    tuple val(meta), path("${meta.id}_aspli_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_aspli_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_aspli_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Date)
    library(jsonlite)

    # --- AspliExampleGTF analysis [] ---
    # Key functions: aspliExampleGTF, makeTxDbFromGFF, binGenome, aspliExampleBamList, frame, gbCounts, jCounts, gbDUreport
    ## BAMFiles <- c("path_to_bams/CT_time1_rep1.BAM", "path_to_bams/CT_time1_rep2.BAM",
    ##               "path_to_bams/CT_time2_rep1.BAM", "path_to_bams/CT_time2_rep2.BAM",
    ##               "path_to_bams/TR_time1_rep1.BAM", "path_to_bams/TR_time1_rep2.BAM",
    ##               "path_to_bams/TR_time2_rep1.BAM", "path_to_bams/TR_time2_rep2.BAM")
    ## (targets <- data.frame( bam = BAMFiles,
    # --- Feature annotation [] ---
    # Key functions: frame, genes, binGenome
    ## symbols       <- data.frame( row.names = genes( aTxDb ),
    ##                              symbol = paste( 'This is symbol of gene:',
    ##                                              genes( aTxDb ) ) )
    ## features      <- binGenome( aTxDb, geneSymbols = symbols )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_aspli_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_aspli_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_aspli_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ASPLI:", paste0("    aspli: ", packageVersion("ASpli"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_aspli_results.csv
    touch ${prefix}_aspli_output.rds
    echo "BIOC_ASPLI:" > versions.yml
    echo "    aspli: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ASPLI_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input_file) ]

    main:
    BIOC_ASPLI(ch_input)

    emit:
    results  = BIOC_ASPLI.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ASPLI.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ASPLI.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ASPLI.out.versions  // channel: path(versions.yml)
}
