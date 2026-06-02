#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: tRNAscanImport
// The package imports the result of tRNAscan-SE as a GRanges object.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/tRNAscanImport/inst/doc/tRNAscanImport.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("tRNAscanImport")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TRNASCANIMPORT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-trnascanimport"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-trnascanimport:1.26.0--r44_0' :
        'quay.io/biocontainers/bioconductor-trnascanimport:1.26.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_trnascanimport_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_trnascanimport_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_trnascanimport_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(tRNAscanImport)
    library(jsonlite)


    # --- Plot1 [] ---
    # Key functions: trnascanimport
    plots$length

    # --- Plot2 [] ---
    # Key functions: trnascanimport
    plots$tRNAscan_score

    # --- Plot3 [] ---
    # Key functions: trnascanimport
    plots$gc

    # --- Plot4 [] ---
    # Key functions: trnascanimport
    plots$tRNAscan_intron

    # --- Plot5 [] ---
    # Key functions: trnascanimport
    plots$variableLoop_length

    # --- T Rna Precursor [] ---
    # Key functions: getSeq, get.tRNAprecursor, sessionInfo, chrmt
    library(BSgenome.Scerevisiae.UCSC.sacCer3)
    genome <- getSeq(BSgenome.Scerevisiae.UCSC.sacCer3)
    # renaming chromosome to match tRNAscan output
    names(genome) <- c(names(genome)[-17L],"chrmt")
    tRNAprecursor <- get.tRNAprecursor(gr, genome)
    head(tRNAprecursor)

    ## -----------------------------------------------------------------------------
    sessionInfo()

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_trnascanimport_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_trnascanimport_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_trnascanimport_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TRNASCANIMPORT:", paste0("    trnascanimport: ", packageVersion("tRNAscanImport"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_trnascanimport_results.csv
    touch ${prefix}_trnascanimport_output.rds
    echo "BIOC_TRNASCANIMPORT:" > versions.yml
    echo "    trnascanimport: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TRNASCANIMPORT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TRNASCANIMPORT(ch_input)

    emit:
    results  = BIOC_TRNASCANIMPORT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TRNASCANIMPORT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TRNASCANIMPORT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TRNASCANIMPORT.out.versions  // channel: path(versions.yml)
}
