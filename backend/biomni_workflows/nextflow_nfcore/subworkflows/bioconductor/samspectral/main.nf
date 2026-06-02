#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SamSPECTRAL
// Samples large data such that spectral clustering is possible while preserving density information in
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SamSPECTRAL/inst/doc/Clustering_by_SamSPECTRAL.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("SamSPECTRAL")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SAMSPECTRAL {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-samspectral"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-samspectral:1.60.0--r44_0' :
        'quay.io/biocontainers/bioconductor-samspectral:1.60.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_samspectral_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_samspectral_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_samspectral_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Building_Communities)
    library(Civilized_Spectral_Clustering)
    library(Conductance_Calculation)
    library(Connecting)
    library(SamSPECTRAL)
    library(jsonlite)

    # --- F Example [] ---
    # Key functions: SamSPECTRAL
    library(SamSPECTRAL)
    set.seed(4)
    data(small_data)
    full <- small
    L <- SamSPECTRAL(full,dimension=c(1,2,3),normal.sigma = 200,
    # --- F Example [] ---
    # Key functions: na
    ## Computing the frequency:
    plot(full, pch='.', col= L)
    frequency <- c()
    minimum.frequency <- 0.01
    ## components smaller than this threshould
    # --- Readfiles2 [] ---
    # Key functions: data
    data(small_data)
    full <- small
    # --- F Sampling [] ---
    # Key functions: Building_Communities
    ## Sample the data and build the communities
    society <-
        Building_Communities(full,m, space.length, community.weakness.threshold)
    plot(full[society$representatives, ], pch=20)
    # --- F Small [] ---
    # Key functions: Conductance_Calculation, Civilized_Spectral_Clustering
    normal.sigma <- 10
    ## Compute conductance between communities
    conductance <- Conductance_Calculation(full, normal.sigma, space.length,
                                           society, precision)
    ## Compute the eigenspace:
    # --- F Large [] ---
    # Key functions: Conductance_Calculation, Civilized_Spectral_Clustering
    normal.sigma <- 1000
    ## Compute conductance between communities
    conductance <- Conductance_Calculation(full, normal.sigma, space.length, society, precision)
    ## Compute the eigenspace:
    if (run.live){
    # --- F Appropriate [] ---
    # Key functions: Conductance_Calculation, Civilized_Spectral_Clustering
    normal.sigma <- 250
    ## Compute conductance between communities
    conductance <- Conductance_Calculation(full, normal.sigma, space.length,
                                           society, precision)
    ## Compute the eigenspace:
    # --- F Lines [] ---
    # Key functions: Civilized_Spectral_Clustering
    ## Fitting two lines:
    clust_result.250 <-
        Civilized_Spectral_Clustering(full, maximum.number.of.clusters,
                                      society, conductance,stabilizer=1,
                                      eigenvalues.num=50)
    # --- F Line [] ---
    # Key functions: Civilized_Spectral_Clustering
    ## Fitting one line:
    clust_result.250 <-
        Civilized_Spectral_Clustering(full, maximum.number.of.clusters,
                                      society, conductance,stabilizer=1,
                                      eigenvalues.num=50, one.line=TRUE)
    # --- F Sep1 [] ---
    # Key functions: Connecting
    ## Extracting labels:
    labels.for_num.of.clusters <- clust_result.250@labels.for_num.of.clusters
    number.of.clusters <- clust_result.250@number.of.clusters
    L33 <- labels.for_num.of.clusters[[number.of.clusters]]
    ## Setting septation factor:
    # --- F Sep2 [] ---
    # Key functions: Connecting
    ## Setting septation factor:
    separation.factor <- 0.5
    ## post-possesing:
    component.of <-
        Connecting(full, society, conductance, number.of.clusters,

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_samspectral_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_samspectral_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_samspectral_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SAMSPECTRAL:", paste0("    samspectral: ", packageVersion("SamSPECTRAL"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_samspectral_results.csv
    touch ${prefix}_samspectral_output.rds
    echo "BIOC_SAMSPECTRAL:" > versions.yml
    echo "    samspectral: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SAMSPECTRAL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SAMSPECTRAL(ch_input)

    emit:
    results  = BIOC_SAMSPECTRAL.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SAMSPECTRAL.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SAMSPECTRAL.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SAMSPECTRAL.out.versions  // channel: path(versions.yml)
}
