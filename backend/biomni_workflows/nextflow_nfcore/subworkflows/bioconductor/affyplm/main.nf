#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: affyPLM
// A package that extends and improves the functionality of the base affy package. Routines that make h
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/affyPLM/inst/doc/AffyExtensions.R
// Upstream  : affydata
// Downstream: bapred
//
// Install: BiocManager::install("affyPLM")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_AFFYPLM {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-affyplm"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-affyplm:1.82.0--r44_0' :
        'quay.io/biocontainers/bioconductor-affyplm:1.82.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_affyplm_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_affyplm_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_affyplm_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(affyPLM)
    library(jsonlite)

    # --- Loaddata [] ---
    # Key functions: updateObject
    library(affyPLM)
    require(affydata)
    data(Dilution)   # an example dataset provided by the affydata package
    ##FIXME: drop this after Dilution is updated
    Dilution = updateObject(Dilution)
    # --- Defaultmodel [] ---
    # Key functions: fitPLM
    Pset <- fitPLM(Dilution)
    # --- Accessors [] ---
    # Key functions: coefs, se
    coefs(Pset)[1:5,]
    se(Pset)[1:5,]
    # --- Seedefaultoutput [] ---
    # Key functions: param
    verify.output.param()
    # --- Noresidnoweights [] ---
    # Key functions: fitPLM
    Pset <- fitPLM(Dilution,output.param=list(residuals=FALSE,weights=FALSE))
    # --- Norobustness [] ---
    # Key functions: fitPLM
    Pset <- fitPLM(Dilution,model.param=list(max.its=0))
    # --- Treatmenteffect [] ---
    # Key functions: fitPLM, geneNames
    Pset <- fitPLM(Dilution,  MM ~ -1 + liver + scanner + probes,subset = geneNames(Dilution)[1:100])
    # --- Treatmenteffectexamine2 [] ---
    # Key functions: probe
    coefs.probe(Pset)[1]
    # --- Treatmenteffectcovariate [] ---
    # Key functions: fitPLM, geneNames, coefs
    logliver <- log2(c(20,20,10,10))
    Pset <- fitPLM(Dilution,model=PM~-1+probes+logliver+scanner, variable.type=c(logliver="covariate"),subset = geneNames(Dilution)[1:100])
    coefs(Pset)[1,]
    # --- Mmcovariate [] ---
    # Key functions: fitPLM, geneNames
    Pset <- fitPLM(Dilution,  PM ~ MM + samples + probes,subset = geneNames(Dilution)[1:100])
    # --- Mmcovariateexamine [] ---
    # Key functions: coefs, const, probe
    coefs(Pset)[1,]
    coefs.const(Pset)[1,]
    coefs.probe(Pset)[1]
    # --- Probetype [] ---
    # Key functions: fitPLM, geneNames
    Pset <- fitPLM(Dilution,  PMMM ~ liver + probe.type + probes,subset = geneNames(Dilution)[1:100])
    # --- Probetypeexamine [] ---
    # Key functions: coefs, const, probe
    coefs(Pset)[1,]
    coefs.const(Pset)[1,]
    coefs.probe(Pset)[1]
    # --- Probesintreatment [] ---
    # Key functions: fitPLM, geneNames
    Pset <- fitPLM(Dilution,  PM ~ -1 + liver + liver:probes,subset = geneNames(Dilution)[1:100])
    # --- Probesintreatmentexamine [] ---
    # Key functions: probe
    coefs.probe(Pset)[1]

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_affyplm_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_affyplm_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_affyplm_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_AFFYPLM:", paste0("    affyplm: ", packageVersion("affyPLM"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_affyplm_results.csv
    touch ${prefix}_affyplm_output.rds
    echo "BIOC_AFFYPLM:" > versions.yml
    echo "    affyplm: 0.0.0" >> versions.yml
    """
}


workflow BIOC_AFFYPLM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_AFFYPLM(ch_input)

    emit:
    results  = BIOC_AFFYPLM.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_AFFYPLM.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_AFFYPLM.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_AFFYPLM.out.versions  // channel: path(versions.yml)
}
