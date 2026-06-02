#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ChIPsim
// A general framework for the simulation of ChIP-seq data. Although currently focused on nucleosome po
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ChIPsim/inst/doc/ChIPsimIntro.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("ChIPsim")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CHIPSIM {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-chipsim"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-chipsim:1.60.0--r44_0' :
        'quay.io/biocontainers/bioconductor-chipsim:1.60.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_chipsim_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_chipsim_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_chipsim_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ChIPsim)
    library(DNAStringSet)
    library(jsonlite)

    # --- Feature Placement [] ---
    # Key functions: placeFeatures
    transition <- list(Binding=c(Background=1),
                       Background=c(Binding=0.05, Background=0.95))
    transition <- lapply(transition, "class<-", "StateDistribution")
    init <- c(Binding=0, Background=1)
    class(init) <- "StateDistribution"
    backgroundFeature <- function(start, length=1000, shape=1, scale=20){
        weight <- rgamma(1, shape=1, scale=20)
        params <- list(start = start, length = length, weight = weight)
        class(params) <- c("Background", "SimulatedFeature")
        params
    }
    bindingFeature <- function(start, length=500, shape=1, scale=20){
        weight <- rgamma(1, shape=1, scale=40)
        params <- list(start = start, length = length, weight = weight)
        class(params) <- c("Binding", "SimulatedFeature")
        params
    }
    generator <- list(Binding=bindingFeature, Background=backgroundFeature)
    features <- ChIPsim::placeFeatures(generator, transition, init,
        start = 0, length = 1e5, globals=list(shape=1, scale=20),
        experimentType="TFExperiment",
        lastFeat=c(Binding = FALSE, Background = TRUE))


    # --- Density Calculation [] ---
    # Key functions: feat2dens, bindDens2readDens
    constRegion <- function(weight, length) rep(weight, length)
    featureDensity.Binding <- function(feature, ...) {
        constRegion(feature$weight, feature$length)
    }
    featureDensity.Background <- function(feature, ...) {
        constRegion(feature$weight, feature$length)
    }
    dens <- ChIPsim::feat2dens(features, length = 1e5)
    fragLength <- function(x, minLength, maxLength, meanLength, ...){
        sd <- (maxLength - minLength)/4
        prob <- dnorm(minLength:maxLength, mean = meanLength, sd = sd)
        prob <- prob/sum(prob)
        prob[x - minLength + 1]
    }
    readDens <- ChIPsim::bindDens2readDens(dens, fragLength, bind = 50,
        minLength = 150, maxLength = 250, meanLength = 200)


    # --- Read Sampling and Simulation [] ---
    # Key functions: sampleReads, defaultFunctions, defaultControl, simChIP
    readLoc <- ChIPsim::sampleReads(readDens, 1e3)
    myFunctions <- ChIPsim::defaultFunctions()
    controlArgs <- ChIPsim::defaultControl(
        features = list(generator = generator, transition = transition,
                        init = init, start = 0, length = 1e5,
                        globals = list(shape = 1, scale = 20),
                        experimentType = "TFExperiment",
                        lastFeat = c(Binding = FALSE, Background = TRUE)),
        readDensity = list(meanLength = 150)
    )
    simulated <- ChIPsim::simChIP(1000, genome, file = "",
        functions = myFunctions, control = controlArgs)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_chipsim_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_chipsim_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_chipsim_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CHIPSIM:", paste0("    chipsim: ", packageVersion("ChIPsim"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_chipsim_results.csv
    touch ${prefix}_chipsim_output.rds
    echo "BIOC_CHIPSIM:" > versions.yml
    echo "    chipsim: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CHIPSIM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CHIPSIM(ch_input)

    emit:
    results  = BIOC_CHIPSIM.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CHIPSIM.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CHIPSIM.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CHIPSIM.out.versions  // channel: path(versions.yml)
}
