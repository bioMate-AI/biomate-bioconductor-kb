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

    # --- Variant Import from VCF [] ---
    # Key functions: variants.from.file
    vcf_file <- system.file("extdata", "chek2.vcf.gz", package = "motifbreakR")
    snps_indel <- variants.from.file(
        file = vcf_file,
        search.genome = BSgenome.Hsapiens.UCSC.hg19::BSgenome.Hsapiens.UCSC.hg19,
        format = "vcf"
    )


    # --- Motif Disruption Analysis [] ---
    # Key functions: motifbreakR
    data("motifbreakR_motif", package = "motifbreakR")
    results <- motifbreakR(
        snpList = snps_mb,
        filterp = TRUE,
        pwmList = motifbreakR_motif[1:10],
        threshold = 1e-4,
        method = "ic",
        bkg = c(A = 0.25, C = 0.25, G = 0.25, T = 0.25),
        BPPARAM = BiocParallel::SerialParam()
    )


    # --- P-Value Estimation [] ---
    # Key functions: calculatePvalue
    results_p <- calculatePvalue(
        results = results,
        BPPARAM = BiocParallel::SerialParam()
    )
    strong_disruptions <- results_p[results_p$effect == "strong"]


    # --- Visualisation [] ---
    # Key functions: plotMB
    plotMB(
        results = results,
        rsid = "rs1006140",
        effect = "strong",
        altAllele = "G"
    )

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
