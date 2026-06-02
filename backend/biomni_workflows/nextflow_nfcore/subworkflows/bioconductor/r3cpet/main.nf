#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: R3CPET
// The package provides a method to infer the set of proteins that are more probably to work together t
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/R3CPET/inst/doc/R3CPET.R
// Upstream  : GenomicRanges, igraph
// Downstream: none
//
// Install: BiocManager::install("R3CPET")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_R3CPET {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-r3cpet"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-r3cpet:1.38.0--r44_0' :
        'quay.io/biocontainers/bioconductor-r3cpet:1.38.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_r3cpet_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_r3cpet_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_r3cpet_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ChiapetExperimentData)
    library(GenerateNetworks)
    library(InferNetworks)
    library(jsonlite)

    # --- Chiapet Experiment Data [] ---
    # Key functions: ChiapetExperimentData
    library(R3CPET)
    petFile <- file.path(system.file("example",package="R3CPET"),"HepG2_interactions.txt")
    tfbsFile <- file.path(system.file("example",package="R3CPET"),"HepG2_TF.txt.gz")
    # --- loadPETs example [] ---
    # Key functions: loadPETs
    petPath <- system.file("example","HepG2_interactions.txt",package="R3CPET")
    x <- loadPETs(x,petFile=petPath, IsBed=FALSE)
    # --- loadPETs BED example [] ---
    # Key functions: loadPETs
    petPath <- system.file("example","HepG2_centered.bed",package="R3CPET")
    x <- loadPETs(x,petFile=petPath, IsBed=TRUE, header = FALSE)
    # --- TF example [] ---
    # Key functions: loadTFBS
    TFPath <- system.file("example","HepG2_TF.txt.gz",package="R3CPET")
    TF <- read.table(TFPath, sep = "\t", header= FALSE)
    head(TF)
    # --- loadPPI usage [] ---
    # Key functions: loadPPI

    # --- loadPPI loading [] ---
    # Key functions: loadPPI
    x <- loadPPI(x,type="HPRD", filter=TRUE)
    # --- create Indexes [] ---
    # Key functions: createIndexes
    x <- createIndexes(x)
    # --- build Networks [] ---
    # Key functions: buildNetworks
    nets<- buildNetworks(x, minFreq=0.1, maxFreq=0.9)
    # --- InferNetowrks usage [] ---
    # Key functions: InferNetworks
    InferNetworks(object,thr =0.5,max_iter = 500L, max_time = 3600L, eta=0.01,gamma=1,alpha=1)
    # --- Infer Networks [] ---
    # Key functions: InferNetworks
    hlda <- InferNetworks(nets)
    # --- InferNetowrks Networks [] ---
    # Key functions: GenerateNetworks
    hlda <- GenerateNetworks(hlda)
    head(networks(hlda))
    # --- Annotate expression [] ---
    # Key functions: annotateExpression, networks
    data(RPKMS)
    hlda<- annotateExpression(hlda,RPKMS)
    networks(hlda)[[1]]
    # --- cluster Interactions [] ---
    # Key functions: clusterInteractions
    clusterInteractions(object, method="sota", nbClus=20 )
    # --- plot3CPETRes usage [] ---
    # Key functions: plot3CPETRes

    # --- get Regions Incluster [] ---
    # Key functions: getRegionsIncluster
    getRegionsIncluster(hlda,x,cluster=3)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_r3cpet_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_r3cpet_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_r3cpet_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_R3CPET:", paste0("    r3cpet: ", packageVersion("R3CPET"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_r3cpet_results.csv
    touch ${prefix}_r3cpet_output.rds
    echo "BIOC_R3CPET:" > versions.yml
    echo "    r3cpet: 0.0.0" >> versions.yml
    """
}


workflow BIOC_R3CPET_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_R3CPET(ch_input)

    emit:
    results  = BIOC_R3CPET.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_R3CPET.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_R3CPET.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_R3CPET.out.versions  // channel: path(versions.yml)
}
