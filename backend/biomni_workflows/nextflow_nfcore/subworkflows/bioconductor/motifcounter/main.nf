#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: motifcounter
// 'motifcounter' provides motif matching, motif counting and motif enrichment functionality based on p
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/motifcounter/inst/doc/motifcounter.R
// Upstream  : MotifDb, knitr, seqLogo
// Downstream: none
//
// Install: BiocManager::install("motifcounter")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MOTIFCOUNTER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-motifcounter"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-motifcounter:1.30.0--r44_0' :
        'quay.io/biocontainers/bioconductor-motifcounter:1.30.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_motifcounter_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_motifcounter_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_motifcounter_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(motifcounter)
    library(jsonlite)

    # --- List [] ---
    # Key functions: query, seqLogo
    ---------------------------------------------------------------------
    # Extract the Oct4 motif from MotifDb
    library(MotifDb)
    oct4 <- as.list(query(query(query(MotifDb, "hsapiens"),
                    "pou5f1"), "jolma2013"))[[1]]
    # --- Normalizemotif [] ---
    # Key functions: normalizeMotif
    ---------------------------------------------------------------------
    new_motif <- normalizeMotif(motif)
    # --- Motifhits [] ---
    # Key functions: motifHits
    ---------------------------------------------------------------------
    # Call putative TFBSs
    mhits <- motifHits(oct4peaks[[1]], motif, bg)
    # Inspect the result
    fhitpos <- which(mhits$fhits == 1)
    # --- Motifcounteroptions [] ---
    # Key functions: motifcounterOptions, motifHits
    ---------------------------------------------------------------------
    # Prescribe a new false positive level for calling TFBSs
    motifcounterOptions(alpha = 0.01)
    # Determine TFBSs
    mhits <- motifHits(oct4peaks[[1]], motif, bg)
    # --- Motifenrichment [] ---
    # Key functions: motifEnrichment
    ---------------------------------------------------------------------
    # Enrichment of Oct4 in Oct4-ChIP-seq peaks
    result <- motifEnrichment(oct4peaks[1:10], motif, bg)
    result

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_motifcounter_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_motifcounter_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_motifcounter_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MOTIFCOUNTER:", paste0("    motifcounter: ", packageVersion("motifcounter"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_motifcounter_results.csv
    touch ${prefix}_motifcounter_output.rds
    echo "BIOC_MOTIFCOUNTER:" > versions.yml
    echo "    motifcounter: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MOTIFCOUNTER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MOTIFCOUNTER(ch_input)

    emit:
    results  = BIOC_MOTIFCOUNTER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MOTIFCOUNTER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MOTIFCOUNTER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MOTIFCOUNTER.out.versions  // channel: path(versions.yml)
}
