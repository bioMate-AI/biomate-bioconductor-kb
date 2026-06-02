#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: coMethDMR
// coMethDMR identifies genomic regions associated with continuous phenotypes by optimally leverages co
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/coMethDMR/inst/doc/vin1_Introduction_to_coMethDMR_geneBasedPipeline.R
// Upstream  : BiocParallel, GenoGAM, corrplot
// Downstream: none
//
// Install: BiocManager::install("coMethDMR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_COMETHDMR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-comethdmr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-comethdmr:1.10.0--r44_0' :
        'quay.io/biocontainers/bioconductor-comethdmr:1.10.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_comethdmr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_comethdmr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_comethdmr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(AnnotateResults)
    library(CoMethAllRegions)
    library(CpGsInfoOneRegion)
    library(GetResiduals)
    library(jsonlite)

    # --- Co Meth All Regions [] ---
    # Key functions: CoMethAllRegions

    # --- lmmTestAllRegions 1 [] ---
    # Key functions: lmmTestAllRegions

    # --- Annotate Results [] ---
    # Key functions: AnnotateResults

    # --- Cp Gs Info One Region [] ---
    # Key functions: CpGsInfoOneRegion

    # --- CpGsInfoOneRegion 2 [] ---
    # Key functions: CpGsInfoOneRegion

    # --- Get Residuals [] ---
    # Key functions: GetResiduals

    # --- CoMethAllRegions 2 [] ---
    # Key functions: CoMethAllRegions

    # --- CoMethAllRegions 3 [] ---
    # Key functions: CoMethAllRegions

    # --- CoMethAllRegions 4 [] ---
    # Key functions: CoMethAllRegions

    # --- lmmTestAllRegions 2 [] ---
    # Key functions: lmmTestAllRegions

    # --- find and test regions [] ---
    # Key functions: CoMethAllRegions, lmmTestAllRegions, AnnotateResults


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_comethdmr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_comethdmr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_comethdmr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_COMETHDMR:", paste0("    comethdmr: ", packageVersion("coMethDMR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_comethdmr_results.csv
    touch ${prefix}_comethdmr_output.rds
    echo "BIOC_COMETHDMR:" > versions.yml
    echo "    comethdmr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_COMETHDMR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_COMETHDMR(ch_input)

    emit:
    results  = BIOC_COMETHDMR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_COMETHDMR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_COMETHDMR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_COMETHDMR.out.versions  // channel: path(versions.yml)
}
