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
    library(Date)
    library(jsonlite)

    # --- Docl [] ---
    # Key functions: getClass
    library(randPack)
    getClass("ClinicalTrial")
    getClass("ClinicalExperiment")
    getClass("PatientID")
    # --- Doadmin [] ---
    # Key functions: new, validPID
    pIDs = new("PatientID",
                strata = c("Center1", "Center2"),
                start = c(1000L, 2000L),
                stop = c(1150L, 2150L)
     )
    # --- Doce [] ---
    # Key functions: new, treatmentFactors, factorNames, numberOfFactorLevels
    trts = c( A = 3L, B = 4L, C = 1L)
    # --- Doct [] ---
    # Key functions: createTrial
    ##  CTvac = createTrial(CEvac, seed=c(301, 401))
    # --- Dora [] ---
    # Key functions: getClass
    getClass("RandomizerDesc")
    getClass("Randomizer")
    getClass("PermutedBlockDesc")
    getClass("PermutedBlock")
    # --- Dohi [] ---
    # Key functions: 24, newPBlock, split
    ##should be 24 (no, 32) long and have one C ever 8 allocs
    table(dempb <- randPack:::.newPBlock(pbdesc))
    bls = rep(1:4, each=8)
    sapply(split(dempb,bls), function(x) sum(x=="C"))
    # --- Dopure [] ---
    # Key functions: new, makeRandomizer, newRandom
    rd = new("RandomDesc", treatments = trts, type = "Random", numPatients = 32L)
    mmpb = makeRandomizer("Expt1", pbdesc, seed = 101)
    mmr = makeRandomizer("Expr1r", rd, seed=201)
    demrd = randPack:::.newRandom(rd)
    table(demrd)
    # --- Lkv [] ---
    # Key functions: createTrial
    CT1 = createTrial(CE1, seed=c(301, 401))
    # --- Mk4 [] ---
    # Key functions: new, Date
    pD1 = new("PatientData", name="Sally H", date=Sys.Date(),
     covariates=list(sex="F", age=33), strata="Center1")
     pD2 = new("PatientData", name="Sally Z", date=Sys.Date(),
     covariates=list(sex="F", age=34), strata="Center1")
    # --- Gett [] ---
    # Key functions: getTreatment
    trt1 = getTreatment(CT1, pD1)
     trt2 = getTreatment(CT1, pD2)
     trt3 = getTreatment(CT1, pD3)
     trt4 = getTreatment(CT1, pD4)
    # --- Gete [] ---
    # Key functions: getEnrolleeInfo
    getEnrolleeInfo(CT1)
    # --- Keepo [] ---
    # Key functions: strataFun
    ##since the strata are Center1 or Center2, we can just pull those
      ##out directly. If the strata were by, say sex and center then we
      ##would need to have some name mangling scheme.
      sFun = function(pDesc) pDesc@strata
    ## patientID class
    # --- Useco [] ---
    # Key functions: new, createTrial, getTreatment
    trts = c( A = 1L, B= 1L)
    bcdesc = new("EfronBiasedCoinDesc", treatments = trts, type="EfronBiasedCoin",
         numPatients=1000L, p=2/3)
    CE1@randomization = list(Center1= list(bcdesc), Center2=list(bcdesc))
    CT2 = createTrial(CE1, seed=c(301, 401))
    # --- Useur [] ---
    # Key functions: new, createTrial, getTreatment
    urndesc = new("UrnDesc", treatments = trts, type="Urn",
         numPatients=1000L, alpha=1, beta=3)
    CE1@randomization = list(Center1= list(urndesc), Center2=list(urndesc))
    CT3 = createTrial(CE1, seed=c(301, 401))
    utrt1 = getTreatment(CT3, pD1)
    # --- Zzz [] ---
    # Key functions: randomization
    randomization(CE1) = list(Center1=list(md), Center2 = list(md))

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
