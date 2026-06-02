#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: BioTIP
// Adopting tipping-point theory to transcriptome profiles to unravel disease regulatory trajectory.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/BioTIP/inst/doc/BioTIP.R
// Upstream  : GenomicRanges
// Downstream: none
//
// Install: BiocManager::install("BioTIP")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BIOTIP {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-biotip"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-biotip:1.20.0--r44_0' :
        'quay.io/biocontainers/bioconductor-biotip:1.20.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_biotip_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_biotip_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_biotip_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BioTIP)
    library(jsonlite)


    # --- Include = False [] ---
    # Key functions: set, row.names, str_split_fixed, group
    knitr::opts_chunk$set(
      collapse = TRUE,
      comment = "#>"
    )
    # load BioTIP and dependent packages
    library(BioTIP)
    library(cluster)
    library(GenomicRanges)
    library(MASS)
    require(stringr)
    require(psych)
    require(igraph)

    ## -----------------------------------------------------------------------------

    # --- Warning=false [] ---
    # Key functions: split, sd_selection, geo_accession, activated, getNetwork, getCluster_methods
    cli$group = factor(cli$group,
                       levels = c('resting','activated','lymphoma_marginal','lymphoma_transitional','lymphoma_aggressive'))
    samplesL <- split(cli[,"geo_accession"],f = cli$group)
    lapply(samplesL, length)
    test <- sd_selection(df, samplesL,0.01)
    head(test[["activated"]])
    igraphL <- getNetwork(test, fdr = 1)
    cluster <- getCluster_methods(igraphL)

    # --- Warning=false [] ---
    # Key functions: simulationMCI, plot_MCI_Simulation, getIc, par, plotIc, simulation_Ic, plot_Ic_Simulation, simulation_Ic_sample
    simuMCI <- simulationMCI(3,samplesL,df, B=100)
    plot_MCI_Simulation(topMCI[1],simuMCI,las=2)

    ## -----------------------------------------------------------------------------
    IC <- getIc(df,samplesL,CTS[[1]],PCC_sample.target = 'average')
    par(mar = c(10,5,0,2))
    plotIc(IC,las = 2)
    simuIC <- simulation_Ic(length(CTS[[1]]),samplesL,df,B=100)
    par(mar = c(10,5,0,2))
    plot_Ic_Simulation(IC,simuIC,las = 2)

    ## -----------------------------------------------------------------------------
    sample_Ic = simulation_Ic_sample(df, sampleNo=3, genes=CTS[[1]], plot=TRUE)
    ##simulated_Ic = plot_simulation_sample(df,length(samplesL[['lymphoma_aggressive']]),IC[['lym#phoma_aggressive']],CTS)

    # --- Warning=false [] ---
    # Key functions: read.delim, outputs, cells, function, samples, trajectory, lengths, logcounts
    #Load stringr library 
    library(stringr)
    #BioTIP dependent libraries 
    library(cluster)
    library(psych)
    library(stringr)
    library(GenomicRanges)
    # library(Hmisc)
    library(MASS)
    library(igraph)
    ## First, estimate the random Ic-scores by permuting the expression values of genes
      RandomIc_g = list()
      set.seed(2020)
      C= 10 # for real data analysis C = at least 500
      i = 1  
      n <- 200 # randomly pick up 200 genes
      RandomIc_g[[i]]  <- simulation_Ic(n, samplesL, counts, 
                                        B=C,
                                        fun="BioTIP")
      names(RandomIc_g)[i] = paste0("Simulation",i,"gene")

    # --- Warning=false [] ---
    # Key functions: getNetwork, getCluster_methods, rainbow, getMCI, save, par, plotBar_MCI, getTopMCI
    ## use 0.01-0.2 to ensure gene-gene co-expression is significant
    ## increase fdr cutoff to obtain larger gene sets
    network.fdr = 0.1
    min.size = 50
    igraphL = getNetwork(subcounts, fdr=network.fdr)
    names(igraphL)

    ## Network partition using random walk
    cluster = getCluster_methods(igraphL)

    fun = 'BioTIP'

    ##  Commented out because of calculation expense, recommend to save the calculated data file after one calculation for future use
    ## membersL = getMCI(cluster, subcounts, adjust.size = F, fun)
    ## save(membersL, file="membersL.RData", compress=TRUE)
    data("membersL")

    par(mar=c(1,1,2,1))
    plotBar_MCI(membersL, ylim=c(0,30), min=50)

    # --- Results=false [] ---
    # Key functions: score, getNextMaxStats, dataset, read.table, class, cor.shrink, save, for
    #### extract CTS scores for each biomodule candidate in the following steps: ####
    ## first to record the max MCI for the n.state.candidate 
    maxMCI <- maxMCI[names(CTS)[1:n.state.candidate]]
    maxMCI

    ## then applendix the 2nd highest MCI score (if existing) for the states with exactly 2 bars
    if(length(whoistop2nd)>0) maxMCI <- c(maxMCI, getNextMaxStats(membersL[['MCI']], idL=maxMCIms[['idx']], whoistop2nd))
    names(maxMCI)
    ## applendix the 2nd highest MCI score (if existing) for the states with exactly 3 bars
    if(length(whoistop3rd)>0) maxMCI <- c(maxMCI, getNextMaxStats(membersL[['MCI']], idL=maxMCIms[['idx']], whoistop3rd))
    ######## verify using IC score #################
    ## First, estimate the random Ic-scores by permuating the expresion values of genes
      RandomIc_g = list()
      set.seed(2020)
      C= 10 # for real data analysis C = at least 500
    #  for(i in 1:length(CTS)){ Not to run the full loop B# } 
      i = 1  
      CTS <- CTS[[i]]
      n <- length(CTS)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_biotip_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_biotip_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_biotip_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BIOTIP:", paste0("    biotip: ", packageVersion("BioTIP"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_biotip_results.csv
    touch ${prefix}_biotip_output.rds
    echo "BIOC_BIOTIP:" > versions.yml
    echo "    biotip: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BIOTIP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BIOTIP(ch_input)

    emit:
    results  = BIOC_BIOTIP.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BIOTIP.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BIOTIP.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BIOTIP.out.versions  // channel: path(versions.yml)
}
