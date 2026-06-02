#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: motifbreakR
// We introduce motifbreakR, which allows the biologist to judge in the first place whether the sequenc
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/motifbreakR/inst/doc/motifbreakR-vignette.R
// Upstream  : BSgenome, MotifDb
// Downstream: none
//
// Install: BiocManager::install("motifbreakR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MOTIFBREAKR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-motifbreakr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-motifbreakr:2.20.0--r44_0' :
        'quay.io/biocontainers/bioconductor-motifbreakr:2.20.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_motifbreakr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_motifbreakr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_motifbreakr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(motifbreakR)
    library(jsonlite)

    # --- plot M B [] ---
    # Key functions: plotMB

    # --- kable [] ---
    # Key functions: kable
    knitr::kable(table(mcols(MotifDb)$organism, mcols(MotifDb)$dataSource), format = "html", table.attr="class=\"table table-striped table-hover\"")
    # --- motifbreak R [] ---
    # Key functions: motifbreakR

    # --- calculate Pvalue [] ---
    # Key functions: calculatePvalue
    rs1006140 <- calculatePvalue(rs1006140, granularity = 1e-6)
    # --- registered [] ---
    # Key functions: registered, bpparam
    BiocParallel::registered()
    BiocParallel::bpparam()
    # --- plot M B [] ---
    # Key functions: plotMB
    plotMB(results = results, rsid = "rs1006140", effect = "strong", altAllele = "G")
    plotMB(results = results, rsid = "rs1006140", effect = "strong", altAllele = "C")
    # --- shiny_motifbreak R [] ---
    # Key functions: shiny_motifbreakR, runApp
    app <- shiny_motifbreakR()
    shiny::runApp(app)
    # --- find Supporting Remap Peaks [] ---
    # Key functions: findSupportingRemapPeaks

    # --- export M Btable [] ---
    # Key functions: exportMBtable
    exportMBtable(results, file = "mb_test_output.tsv", format = "tsv")
    # --- export M Bbed [] ---
    # Key functions: exportMBbed
    exportMBbed(results, file = "mb_test_output.bed", color = "effect_size")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_motifbreakr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_motifbreakr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_motifbreakr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MOTIFBREAKR:", paste0("    motifbreakr: ", packageVersion("motifbreakR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_motifbreakr_results.csv
    touch ${prefix}_motifbreakr_output.rds
    echo "BIOC_MOTIFBREAKR:" > versions.yml
    echo "    motifbreakr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MOTIFBREAKR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MOTIFBREAKR(ch_input)

    emit:
    results  = BIOC_MOTIFBREAKR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MOTIFBREAKR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MOTIFBREAKR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MOTIFBREAKR.out.versions  // channel: path(versions.yml)
}
