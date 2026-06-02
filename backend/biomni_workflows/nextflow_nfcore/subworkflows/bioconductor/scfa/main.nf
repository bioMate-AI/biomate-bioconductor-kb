#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SCFA
// Subtyping via Consensus Factor Analysis (SCFA) can efficiently remove noisy signals from consistent 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SCFA/inst/doc/Example.R
// Upstream  : knitr, survival
// Downstream: none
//
// Install: BiocManager::install("SCFA")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SCFA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-scfa"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-scfa:1.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-scfa:1.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_scfa_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_scfa_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_scfa_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SCFA)
    library(jsonlite)


    # --- Eval=true [] ---
    # Key functions: scfa
    #Load required library
    library(SCFA)
    library(survival)

    # Load example data (GBM dataset), for other dataset, download the rds file from the Data folder at https://bioinformatics.cse.unr.edu/software/scfa/Data/ and load the rds object
    data("GBM")
    # List of one matrix of microRNA data, other examples would have 3 matrices of 3 data types
    dataList <- GBM$data
    # Survival information
    survival <- GBM$survival

    # --- Eval=true [] ---
    # Key functions: SCFA, coxph, Surv, summary, exact
    # Generating subtyping result
    set.seed(1)
    subtype <- SCFA(dataList, seed = 1, ncores = 4L)

    # Perform survival analysis on the result
    coxFit <- coxph(Surv(time = Survival, event = Death) ~ as.factor(subtype), data = survival, ties="exact")
    coxP <- round(summary(coxFit)$sctest[3],digits = 20)
    print(coxP)

    # --- Eval=true [] ---
    # Key functions: sample.int, function, Surv, SCFA.class
    # Split data to train and test
    set.seed(1)
    idx <- sample.int(nrow(dataList[[1]]), round(nrow(dataList[[1]])/2) )

    survival$Survival <- survival$Survival - min(survival$Survival) + 1 # Survival time must be positive

    trainList <- lapply(dataList, function(x) x[idx, ] )
    trainSurvival <- Surv(time = survival[idx,]$Survival, event =  survival[idx,]$Death)

    testList <- lapply(dataList, function(x) x[-idx, ] )
    testSurvival <- Surv(time = survival[-idx,]$Survival, event =  survival[-idx,]$Death)

    # Perform risk prediction
    result <- SCFA.class(trainList, trainSurvival, testList, seed = 1, ncores = 4L)


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_scfa_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_scfa_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_scfa_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SCFA:", paste0("    scfa: ", packageVersion("SCFA"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_scfa_results.csv
    touch ${prefix}_scfa_output.rds
    echo "BIOC_SCFA:" > versions.yml
    echo "    scfa: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SCFA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SCFA(ch_input)

    emit:
    results  = BIOC_SCFA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SCFA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SCFA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SCFA.out.versions  // channel: path(versions.yml)
}
