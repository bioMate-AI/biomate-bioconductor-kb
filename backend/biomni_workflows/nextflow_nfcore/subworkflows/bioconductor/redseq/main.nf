#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: REDseq
// The package includes functions to build restriction enzyme cut site (RECS) map, distribute mapped se
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/REDseq/inst/doc/REDseq.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("REDseq")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_REDSEQ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-redseq"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-redseq:1.52.0--r44_0' :
        'quay.io/biocontainers/bioconductor-redseq:1.52.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_redseq_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_redseq_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_redseq_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(REDseq)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: assignSeq2REsite
    data(example.REDseq)
    	data(example.map)
    	r.unique = assignSeq2REsite(example.REDseq, example.map, cut.offset = 1,
    	seq.length = 36, allowed.offset = 5, min.FragmentLength = 60,
    	max.FragmentLength = 300, partitionMultipleRE = "unique")
    # --- Data [] ---
    # Key functions: data
    data(example.assignedREDseq)
    # --- Fig1 [] ---
    # Key functions: plotCutDistribution
    plotCutDistribution(example.assignedREDseq,example.map, chr="2",
    xlim =c(3012000, 3020000))
    # --- Fig2 [] ---
    # Key functions: distanceHistSeq2RE
    distanceHistSeq2RE(example.assignedREDseq,ylim=c(0,25))
    # --- Summarizebyre [] ---
    # Key functions: summarizeByRE
    REsummary  =summarizeByRE(example.assignedREDseq,by="Weight")
    # --- Redseq [] ---
    # Key functions: REDseq
    binom.test.REDseq(REsummary)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_redseq_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_redseq_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_redseq_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_REDSEQ:", paste0("    redseq: ", packageVersion("REDseq"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_redseq_results.csv
    touch ${prefix}_redseq_output.rds
    echo "BIOC_REDSEQ:" > versions.yml
    echo "    redseq: 0.0.0" >> versions.yml
    """
}


workflow BIOC_REDSEQ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_REDSEQ(ch_input)

    emit:
    results  = BIOC_REDSEQ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_REDSEQ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_REDSEQ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_REDSEQ.out.versions  // channel: path(versions.yml)
}
