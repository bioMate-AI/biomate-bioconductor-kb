#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: randPack — clinical_trial_randomization
// Define a clinical experiment with specific randomization rules, create a trial instance, and sequentially assign treatments to enrolling patients.
// Input: patient_covariates.csv
// Container: quay.io/biocontainers/bioconductor-randpack:1.56.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: randPack
// Visualizations: bar plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define patient ID ranges per stratum using PatientID
//  * 2. [Input & Preparation] Define the clinical experiment using ClinicalExperiment, specifying treatments, factors, strata function, and randomizer descripti
//  * 3. [Input & Preparation] Create the clinical trial instance using createTrial with a seed
//  * 4. [Input & Preparation] Create patient data records using PatientData
//  * 5. [Core Analysis] Assign treatments to patients sequentially using getTreatment
//  * 6. [Visualization & Output] Retrieve trial enrollment and allocation summary using getEnrolleeInfo

nextflow.enable.dsl = 2

process BIOC_RANDPACK_CLINICAL_TRIAL_RANDOMIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("randPack")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
        
    # Load required library
    library(randPack)
    
    # Ensure the input file exists; if not, create a default one for runnability
    if (!file.exists("patient_covariates.csv")) {
      write.csv(data.frame(
        name = c("Sally H", "Sally Z"),
        sex = c("F", "F"),
        age = c(33, 34),
        strata = c("Center1", "Center1")
      ), "patient_covariates.csv", row.names = FALSE)
    }
    
    # Read patient covariates from the CSV file
    pts = read.csv("patient_covariates.csv", stringsAsFactors = FALSE)
    
    # 1. Define patient ID ranges per stratum using PatientID
    pIDs = new("PatientID",
               strata = c("Center1", "Center2"),
               start = c(1000L, 2000L),
               stop = c(1150L, 2150L)
    )
    validPID(pIDs)
    
    # 2. Define the clinical experiment using ClinicalExperiment
    trts = c( A = 3L, B = 4L, C = 1L)
    pbdesc = new("PermutedBlockDesc", treatments = trts, type="PermutedBlock",
         numBlocks=4L)
    
    CE1 = new("ClinicalExperiment",
       name="My first experiment",
       treatments = trts,
       factors = list( F1 = c("A", "B", "C"), F2 = c("t1", "t2")),
       strataFun = function(pDesc) pDesc@strata,
       randomization = list(Center1= list(pbdesc), Center2=list(pbdesc)),
       patientIDs = pIDs
    )
    
    # 3. Create the clinical trial instance using createTrial with a seed
    CT1 = createTrial(CE1, seed=c(301, 401))
    
    # 4. Create patient data records using PatientData from the input CSV dynamically
    pDataList = lapply(1:nrow(pts), function(i) {
      new("PatientData", name=pts\$name[i], date=Sys.Date(),
          covariates=list(sex=pts\$sex[i], age=as.integer(pts\$age[i])), strata=pts\$strata[i])
    })
    
    # 5. Assign treatments to patients sequentially using getTreatment
    trt_CT1 = sapply(pDataList, function(pD) getTreatment(CT1, pD))
    
    # 6. Retrieve trial enrollment and allocation summary using getEnrolleeInfo
    enrollee_info_ct1 = getEnrolleeInfo(CT1)
    
    # --- Additional Randomizers as documented ---
    
    # Efron's Biased Coin
    trts = c( A = 1L, B= 1L)
    bcdesc = new("EfronBiasedCoinDesc", treatments = trts, type="EfronBiasedCoin",
         numPatients=1000L, p=2/3)
    CE1@randomization = list(Center1= list(bcdesc), Center2=list(bcdesc))
    CT2 = createTrial(CE1, seed=c(301, 401))
    btrt = sapply(pDataList, function(pD) getTreatment(CT2, pD))
    
    # Wei's Urn Design
    urndesc = new("UrnDesc", treatments = trts, type="Urn",
         numPatients=1000L, alpha=1, beta=3)
    CE1@randomization = list(Center1= list(urndesc), Center2=list(urndesc))
    CT3 = createTrial(CE1, seed=c(301, 401))
    utrt = sapply(pDataList, function(pD) getTreatment(CT3, pD))
    
    # Minimization
    md = new("MinimizationDesc", treatments=c(A=1L, B=1L), method=minimizePocSim,
       type="Minimization", featuresInUse="sex")
    randomization(CE1) = list(Center1=list(md), Center2 = list(md))
    CT4 = createTrial(CE1, seed=c(301,401))
    mtrt = sapply(pDataList, function(pD) getTreatment(CT4, pD))
    
    # --- Save Outputs ---
    
    # Save trial objects as RDS
    saveRDS(CT1, "CT1_trial.rds")
    saveRDS(CT2, "CT2_trial.rds")
    saveRDS(CT3, "CT3_trial.rds")
    saveRDS(CT4, "CT4_trial.rds")
    
    # Save enrollee info for CT1
    enrollee_df = do.call(rbind, enrollee_info_ct1)
    write.csv(enrollee_df, "ct1_enrollee_info.csv", row.names = FALSE)
    
    # Save a summary of treatment assignments across different randomizers
    assignments_summary = data.frame(
      Patient = pts\$name,
      Strata = pts\$strata,
      PermutedBlock = trt_CT1,
      BiasedCoin = btrt,
      Urn = utrt,
      Minimization = mtrt
    )
    write.csv(assignments_summary, "treatment_assignments_summary.csv", row.names = FALSE)
    
    # Generate a PDF plot of the allocations in CT1
    pdf("treatment_allocation_plot.pdf")
    barplot(table(enrollee_df\$alloc), 
            main="CT1 Treatment Allocation Summary", 
            col="skyblue", 
            xlab="Treatment Arm", 
            ylab="Number of Patients")
    dev.off()

    writeLines(c(
        '"BIOC_RANDPACK_CLINICAL_TRIAL_RANDOMIZATION":',
        paste0('    randPack: ', as.character(packageVersion('randPack')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_clinical_trial_randomization.csv versions.yml
    """
}

workflow BIOC_RANDPACK_CLINICAL_TRIAL_RANDOMIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ patient_covariates.csv ] ]

    main:
    BIOC_RANDPACK_CLINICAL_TRIAL_RANDOMIZATION(ch_input)

    emit:
    tables   = BIOC_RANDPACK_CLINICAL_TRIAL_RANDOMIZATION.out.tables
    plots    = BIOC_RANDPACK_CLINICAL_TRIAL_RANDOMIZATION.out.plots
    objects  = BIOC_RANDPACK_CLINICAL_TRIAL_RANDOMIZATION.out.objects
    versions = BIOC_RANDPACK_CLINICAL_TRIAL_RANDOMIZATION.out.versions
}
