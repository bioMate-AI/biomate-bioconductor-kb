#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: randPack
// A suite of classes and functions for randomizing patients in clinical trials.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/randPack/inst/doc/randPack.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("randPack")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RANDPACK {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-randpack"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-randpack:1.52.0--r44_0' :
        'quay.io/biocontainers/bioconductor-randpack:1.52.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_randpack_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_randpack_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_randpack_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(randPack)
    library(Date)
    library(jsonlite)

    # --- Randomizer Creation and Trial Initialization [] ---
    # Key functions: makeRandomizer, createTrial
    pbdesc <- new("PermutedBlockDesc",
        treatments = c(A = 3L, B = 4L, C = 1L),
        type = "PermutedBlock",
        numBlocks = 4L
    )
    mmpb <- makeRandomizer("Expt1", pbdesc, seed = 101)
    CE1 <- new("ClinicalExperiment",
        name = "My first experiment",
        treatments = c(A = 3L, B = 4L, C = 1L),
        factors = list(F1 = c("A", "B", "C"), F2 = c("t1", "t2")),
        strataFun = function(pDesc) pDesc@strata,
        randomization = list(Center1 = list(pbdesc), Center2 = list(pbdesc)),
        patientIDs = pIDs
    )
    CT1 <- createTrial(CE1, seed = c(301, 401))


    # --- Patient Enrollment and Treatment Allocation [] ---
    # Key functions: getTreatment, getEnrolleeInfo
    pD1 <- new("PatientData", name = "Sally H", date = Sys.Date(),
        covariates = list(sex = "F", age = 33), strata = "Center1")
    pD2 <- new("PatientData", name = "Sally Z", date = Sys.Date(),
        covariates = list(sex = "F", age = 34), strata = "Center1")
    trt1 <- getTreatment(CT1, pD1)
    trt2 <- getTreatment(CT1, pD2)
    enrollee_info <- getEnrolleeInfo(CT1)


    # --- Biased Coin and Urn Randomization [] ---
    # Key functions: createTrial, getTreatment
    trts <- c(A = 1L, B = 1L)
    bcdesc <- new("EfronBiasedCoinDesc", treatments = trts,
        type = "EfronBiasedCoin", numPatients = 1000L, p = 2/3)
    CE1@randomization <- list(Center1 = list(bcdesc), Center2 = list(bcdesc))
    CT2 <- createTrial(CE1, seed = c(301, 401))
    btrt1 <- getTreatment(CT2, pD1)
    btrt2 <- getTreatment(CT2, pD2)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_randpack_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_randpack_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_randpack_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RANDPACK:", paste0("    randpack: ", packageVersion("randPack"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_randpack_results.csv
    touch ${prefix}_randpack_output.rds
    echo "BIOC_RANDPACK:" > versions.yml
    echo "    randpack: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RANDPACK_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RANDPACK(ch_input)

    emit:
    results  = BIOC_RANDPACK.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RANDPACK.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RANDPACK.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RANDPACK.out.versions  // channel: path(versions.yml)
}
