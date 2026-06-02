#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: BasicSTARRseq
// Basic peak calling on STARR-seq data based on a method introduced in "Genome-Wide Quantitative Enhan
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/BasicSTARRseq/inst/doc/BasicSTARRseq.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("BasicSTARRseq")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BASICSTARRSEQ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-basicstarrseq"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-basicstarrseq:1.34.0--r44_0' :
        'quay.io/biocontainers/bioconductor-basicstarrseq:1.34.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_basicstarrseq_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_basicstarrseq_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_basicstarrseq_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(STARRseqData)
    library(jsonlite)

    # --- Basicstarrseq.Rnw:39 45 [] ---
    # Key functions: STARRseqData
    starrseqFileName <- system.file("extdata", "smallSTARR.bam",
                                    package="BasicSTARRseq")
    inputFileName <- system.file("extdata", "smallInput.bam",
                                 package="BasicSTARRseq")
    # --- Basicstarrseq.Rnw:48 50 [] ---
    # Key functions: STARRseqData
    STARRseqData(sample=starrseqFileName, control=inputFileName,
                 pairedEnd=FALSE)
    # --- Basicstarrseq.Rnw:53 57 [] ---
    # Key functions: granges, readGAlignmentPairs, STARRseqData
    starrseqGRanges <- granges(readGAlignmentPairs(starrseqFileName))
    inputGRanges <- granges(readGAlignmentPairs(inputFileName))
    data <- STARRseqData(sample=starrseqGRanges, control=inputGRanges)
    data
    # --- Basicstarrseq.Rnw:62 64 [] ---
    # Key functions: getPeaks
    peaks <- getPeaks(data)
    peaks

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_basicstarrseq_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_basicstarrseq_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_basicstarrseq_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BASICSTARRSEQ:", paste0("    basicstarrseq: ", packageVersion("BasicSTARRseq"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_basicstarrseq_results.csv
    touch ${prefix}_basicstarrseq_output.rds
    echo "BIOC_BASICSTARRSEQ:" > versions.yml
    echo "    basicstarrseq: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BASICSTARRSEQ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BASICSTARRSEQ(ch_input)

    emit:
    results  = BIOC_BASICSTARRSEQ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BASICSTARRSEQ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BASICSTARRSEQ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BASICSTARRSEQ.out.versions  // channel: path(versions.yml)
}
