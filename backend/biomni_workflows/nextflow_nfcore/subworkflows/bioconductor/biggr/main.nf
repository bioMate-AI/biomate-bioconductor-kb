#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: BiGGR
// This package provides an interface to simulate metabolic reconstruction from the BiGG database(http:
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/BiGGR/inst/doc/BiGGR.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("BiGGR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BIGGR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-biggr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-biggr:1.42.0--r44_0' :
        'quay.io/biocontainers/bioconductor-biggr:1.42.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_biggr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_biggr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_biggr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BiGGR)
    library(jsonlite)

    # --- Eq Ineq [] ---
    # Key functions: tempfile, createLIMFromSBML
    ##load lying-tunell data
    data(lying.tunell.data)
    ##set equality constraints
    equation.vars <- c("R_GLCt1r", "R_L_LACt2r", "R_GLNtN1",
                       "R_PYRt2r", "R_GLUDC", "R_G6PDH2r")
    # --- Sample Flux Ensemble [] ---
    # Key functions: frame, tempfile, createLIMFromSBML, sampleFluxEnsemble
    ##specify the fluxes with uncertainty given as SD in a data frame
    uncertain.vars <- data.frame(var=equation.vars[1:4],
                                 value=equation.values[1:4],
                                 sd=c(0.058,0.032,0.034,0.004))
    uncertain.vars <- data.frame(var=c(equation.vars[c(1,2,3,4)]),
    # --- Fig Tca [] ---
    # Key functions: sbml2hyperdraw
    relevant.species <- c("M_cit_m", "M_icit_m" , "M_akg_m",
                          "M_succoa_m", "M_succ_m", "M_fum_m",
                          "M_mal_DASH_L_m", "M_oaa_m")
    relevant.reactions <- c("R_CSm", "R_ACONTm", "R_ICDHxm",
                            "R_AKGDm", "R_SUCOAS1m", "R_SUCD1m",

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_biggr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_biggr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_biggr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BIGGR:", paste0("    biggr: ", packageVersion("BiGGR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_biggr_results.csv
    touch ${prefix}_biggr_output.rds
    echo "BIOC_BIGGR:" > versions.yml
    echo "    biggr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BIGGR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BIGGR(ch_input)

    emit:
    results  = BIOC_BIGGR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BIGGR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BIGGR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BIGGR.out.versions  // channel: path(versions.yml)
}
