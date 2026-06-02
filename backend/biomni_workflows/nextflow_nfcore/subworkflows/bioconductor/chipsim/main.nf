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
    library(DNAStringSet)
    library(jsonlite)

    # --- Genome [] ---
    # Key functions: sample, DNAStringSet
    chrLen <- c(2e5, 1e5)
    chromosomes <- sapply(chrLen, function(n) paste(sample(DNA_BASES, n, replace = TRUE), collapse = ""))
    names(chromosomes) <- paste("CHR", seq_along(chromosomes), sep="")
    genome <- DNAStringSet(chromosomes)
    # --- Simulatequalities [] ---
    # Key functions: sample, unlist, rawToChar, raw
    randomQuality <- function(read, ...){
    	paste(sample(unlist(strsplit(rawToChar(as.raw(64:104)),"")),
    					nchar(read), replace = TRUE), collapse="")
    }
    # --- Output [] ---
    # Key functions: readSequence

    # --- Simulation [] ---
    # Key functions: defaultFunctions, simChIP, defaultControl
    myFunctions <- defaultFunctions()
    myFunctions$readSequence <- dfReads
    nReads <- 1000
    simulated <- simChIP(nReads, genome, file = "", functions = myFunctions,
    		control = defaultControl(readDensity=list(meanLength = 150)))
    # --- Which [] ---
    # Key functions: density
    ## feat <- simulated$features[[1]]
    ## stableIdx <- which(sapply(feat, inherits, "StableFeature"))
    ## start <- feat[[stableIdx[1]]]$start
    ## plot((start-2000):(start+500), simulated$bindDensity[[1]][(start-2000):(start+500)], xlab="Chromosome 1",
    ## 		ylab="Density", type='l')
    # --- Bgemission [] ---
    # Key functions: rgamma

    # --- Bindingemission [] ---
    # Key functions: rpareto1

    # --- Features1 1 [] ---
    # Key functions: makeFeatures
    set.seed(1)
     generator <- list(Binding=bindingFeature, Background=backgroundFeature)
     features <- ChIPsim::makeFeatures(generator, transition, init, start = 0, length = 1e6, globals=list(shape=1, scale=20),
    		 experimentType="TFExperiment", lastFeat=c(Binding = FALSE, Background = TRUE))
    # --- Sapply [] ---
    # Key functions: density
    bindIdx <- sapply(features, inherits, "Binding")
    # --- Features1 2 [] ---
    # Key functions: placeFeatures
    set.seed(1)
     features <- ChIPsim::placeFeatures(generator, transition, init, start = 0, length = 1e6, globals=list(shape=1, scale=20),
    		 experimentType="TFExperiment", lastFeat=c(Binding = FALSE, Background = TRUE))
    # --- Featuredensity1 [] ---
    # Key functions: constRegion
    constRegion <- function(weight, length) rep(weight, length)
    featureDensity.Binding <- function(feature, ...) constRegion(feature$weight, feature$length)
    featureDensity.Background <- function(feature, ...) constRegion(feature$weight, feature$length)
    # --- Density1 [] ---
    # Key functions: feat2dens
    dens <- ChIPsim::feat2dens(features)
    # --- Readloc1 [] ---
    # Key functions: sample
    readLoc <- sample(44000:64000, 1e3, prob=dens[44000:64000], replace=TRUE)
    # --- Reconcilefeatures [] ---
    # Key functions: any, inherits

    # --- Features2 [] ---
    # Key functions: placeFeatures
    set.seed(1)
     features <- ChIPsim::placeFeatures(generator, transition, init, start = 0, length = 1e6, globals=list(shape=1, scale=20),
    		 experimentType="TFExperiment", lastFeat=c(Binding = FALSE, Background = TRUE),
    		 control=list(Binding=list(length=50)))

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
