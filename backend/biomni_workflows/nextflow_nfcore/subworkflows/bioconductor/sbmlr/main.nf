#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SBMLR
// This package contains a systems biology markup language (SBML) interface to R.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SBMLR/inst/doc/quick-start.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("SBMLR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SBMLR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-sbmlr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-sbmlr:2.2.0--r44_0' :
        'quay.io/biocontainers/bioconductor-sbmlr:2.2.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_sbmlr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_sbmlr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_sbmlr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SBMLR)
    library(jsonlite)

    # --- Equality [] ---
    # Key functions: readSBML, readSBMLR
    curtoX=readSBML("curto.xml")
    curtoR=readSBMLR("curto.r")
    head((curtoX==curtoR)$species)
    head((curtoX==curtoR)$reactions)
    # --- Simulation [] ---
    # Key functions: sim, frame, attach
    out1=sim(curto,seq(-20,0,1))
    curto$species$PRPP$ic=50
    out2=sim(curto,0:70)
    outs=data.frame(rbind(out1,out2))
    attach(outs)
    # --- Bumplessxfer [] ---
    # Key functions: sim
    curto$species$PRPP$ic=5  # return PRPP IC to its original value
    sim(curto,(-10):10,modulator=rep(2,37)) # bumpless transfer in concentrations since all V increase by 2
    # --- Unstable [] ---
    # Key functions: sim
    sim(curto,(-10):10,modulator=c(rep(1.1,20),rep(0.9,17))) # half up, half down, not bumpless
    # --- Folatesim [] ---
    # Key functions: readSBML, path, sim, frame, attach
    morr=readSBML(file.path(system.file(package="SBMLR"), "models/morrison.xml"))
    out1=sim(morr,seq(-20,0,1))
    morr$species$EMTX$ic=1 # bolus of methotrexate to 1 uM
    out2=sim(morr,0:30)
    outs=data.frame(rbind(out1,out2))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_sbmlr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_sbmlr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_sbmlr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SBMLR:", paste0("    sbmlr: ", packageVersion("SBMLR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sbmlr_results.csv
    touch ${prefix}_sbmlr_output.rds
    echo "BIOC_SBMLR:" > versions.yml
    echo "    sbmlr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SBMLR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SBMLR(ch_input)

    emit:
    results  = BIOC_SBMLR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SBMLR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SBMLR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SBMLR.out.versions  // channel: path(versions.yml)
}
