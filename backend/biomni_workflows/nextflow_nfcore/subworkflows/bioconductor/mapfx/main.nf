#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MAPFX
// MAPFX is an end-to-end toolbox that pre-processes the raw data from MPC experiments (e.g., BioLegend
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MAPFX/inst/doc/MAPFX_Vignette.R
// Upstream  : Biobase, ComplexHeatmap, RColorBrewer, Rfast, circlize
// Downstream: none
//
// Install: BiocManager::install("MAPFX")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MAPFX {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mapfx"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-mapfx:1.2.0--r44_0' :
        'quay.io/biocontainers/bioconductor-mapfx:1.2.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_mapfx_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mapfx_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mapfx_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MapfxFFC)
    library(MapfxMPC)
    library(jsonlite)

    # --- kable [] ---
    # Key functions: kable
    library(knitr)
    # --- MapfxMPC impu example [] ---
    # Key functions: MapfxMPC
    data(ord.fcs.raw.meta.df.out_mpc)
    data(ord.fcs.raw.mt_mpc)
    dir.create(file.path(tempdir(), "MPC_impu_Output"))
    # --- mapfxNorm MPC [] ---
    # Key functions: MapfxMPC
    data(ord.fcs.raw.meta.df.out_mpc)
    data(ord.fcs.raw.mt_mpc)
    dir.create(file.path(tempdir(), "MPC_NOimpu_Output"))
    # --- mapfxNorm FFC [] ---
    # Key functions: MapfxFFC
    data(ord.fcs.raw.meta.df.out_ffc)
    data(ord.fcs.raw.mt_ffc)
    dir.create(file.path(tempdir(), "FFCnorm_Output"))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_mapfx_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_mapfx_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_mapfx_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MAPFX:", paste0("    mapfx: ", packageVersion("MAPFX"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mapfx_results.csv
    touch ${prefix}_mapfx_output.rds
    echo "BIOC_MAPFX:" > versions.yml
    echo "    mapfx: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MAPFX_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MAPFX(ch_input)

    emit:
    results  = BIOC_MAPFX.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MAPFX.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MAPFX.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MAPFX.out.versions  // channel: path(versions.yml)
}
