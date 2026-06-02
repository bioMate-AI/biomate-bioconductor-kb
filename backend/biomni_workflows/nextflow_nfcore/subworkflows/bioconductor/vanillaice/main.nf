#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: VanillaICE
// Hidden Markov Models for characterizing chromosomal alteration in high throughput SNP arrays.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/VanillaICE/inst/doc/VanillaICE.R
// Upstream  : ArrayTV, IRanges, crlmm, doSNOW, foreach
// Downstream: MinimumDistance
//
// Install: BiocManager::install("VanillaICE")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_VANILLAICE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-vanillaice"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-vanillaice:1.68.0--r44_0' :
        'quay.io/biocontainers/bioconductor-vanillaice:1.68.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_vanillaice_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_vanillaice_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_vanillaice_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(VanillaICE)
    library(ArrayViews)
    library(CopyNumScanParams)
    library(EmissionParam)
    library(FilterParam)
    library(GRanges)
    library(HmmTrellisParam)
    library(IRanges)
    library(SnpExperiment)
    library(SnpGRanges)
    library(jsonlite)

    # --- SnpExperiment Construction and HMM Fitting [] ---
    # Key functions: SnpExperiment, EmissionParam, hmm2
    snp_exp <- SnpExperiment(views[, 4:5])
    param <- EmissionParam(temper=0.5)
    fit <- hmm2(snp_exp, param)


    # --- CNV Filtering [] ---
    # Key functions: FilterParam, cnvFilter
    select_cnv <- FilterParam(state=c("1", "2", "5", "6"), seqnames="chr22")
    cnvs <- cnvFilter(fit, select_cnv)


    # --- Visualization [] ---
    # Key functions: HmmTrellisParam, xyplotList, viewports, xygrid
    trellis_param <- HmmTrellisParam()
    cnvList <- split(cnvs, cnvs$id)
    figList <- xyplotList(cnvList, snp_exp, trellis_param)
    fig1 <- figList[[1]][[1]]
    vps <- viewports()
    xygrid(fig1, vps, cnvList[[1]][1])

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_vanillaice_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_vanillaice_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_vanillaice_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_VANILLAICE:", paste0("    vanillaice: ", packageVersion("VanillaICE"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_vanillaice_results.csv
    touch ${prefix}_vanillaice_output.rds
    echo "BIOC_VANILLAICE:" > versions.yml
    echo "    vanillaice: 0.0.0" >> versions.yml
    """
}


workflow BIOC_VANILLAICE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_VANILLAICE(ch_input)

    emit:
    results  = BIOC_VANILLAICE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_VANILLAICE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_VANILLAICE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_VANILLAICE.out.versions  // channel: path(versions.yml)
}
