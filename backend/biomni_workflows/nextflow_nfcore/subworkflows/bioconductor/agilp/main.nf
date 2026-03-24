#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: agilp
// More about what it does (maybe more than one line)
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/agilp/inst/doc/agilp_manual.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("agilp")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_AGILP {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-agilp"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-agilp:3.38.0--r44_0' :
        'quay.io/biocontainers/bioconductor-agilp:3.38.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_agilp_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_agilp_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_agilp_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(AALoess)
    library(Baseline)
    library(IDswop)
    library(Loader)
    library(jsonlite)

    # --- Unlink [] ---
    # Key functions: unlink, path
    unlink(file.path(system.file(package="agilp"),"output","","*.*",
    fsep = .Platform$file.sep), recursive=FALSE)
    # --- Baseline [] ---
    # Key functions: Baseline
    Baseline(NORM="FALSE",allfiles="FALSE",r=2,A=2,B=5,input=inputdir, baseout=outputbase, t = template)
    # --- Unlink [] ---
    # Key functions: unlink, path
    unlink(file.path(system.file(package="agilp"),"output","","*.*",
    fsep = .Platform$file.sep), recursive=FALSE)
    # --- Loader [] ---
    # Key functions: Loader
    Loader(input=inputdir,output=outputdir,t=template,f="FALSE",r=2,A=2,B=5)
    dim(dataout)
    # --- Unlink [] ---
    # Key functions: unlink, path
    unlink(file.path(system.file(package="agilp"),"output","","*.*",
    fsep = .Platform$file.sep), recursive=FALSE)
    # --- Aaloess [] ---
    # Key functions: AALoess
    AALoess(input=inputdir, output=outputdir, baseline = baselinedir, LOG="FALSE")
    # --- Unlink [] ---
    # Key functions: unlink, path
    unlink(file.path(system.file(package="agilp"),"output","","*.*",
    fsep = .Platform$file.sep), recursive=FALSE)
    # --- Idswop [] ---
    # Key functions: IDswop
    IDswop(input=inputdir,output=outputdir,annotation=annotation,source_ID="ProbeID",
    target_ID="EnsemblID", ERR=1)
    # --- Unlink [] ---
    # Key functions: unlink, path
    unlink(file.path(system.file(package="agilp"),"output","","*.*",
    fsep = .Platform$file.sep), recursive=FALSE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_agilp_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_agilp_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_agilp_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_AGILP:", paste0("    agilp: ", packageVersion("agilp"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_agilp_results.csv
    touch ${prefix}_agilp_output.rds
    echo "BIOC_AGILP:" > versions.yml
    echo "    agilp: 0.0.0" >> versions.yml
    """
}


workflow BIOC_AGILP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_AGILP(ch_input)

    emit:
    results  = BIOC_AGILP.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_AGILP.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_AGILP.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_AGILP.out.versions  // channel: path(versions.yml)
}
