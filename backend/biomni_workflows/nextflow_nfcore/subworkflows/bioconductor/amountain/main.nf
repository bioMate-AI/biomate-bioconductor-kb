#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: AMOUNTAIN
// A pure data-driven gene network, weighted gene co-expression network (WGCN) could be constructed onl
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/AMOUNTAIN/inst/doc/AMOUNTAIN.R
// Upstream  : qgraph
// Downstream: none
//
// Install: BiocManager::install("AMOUNTAIN")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_AMOUNTAIN {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-amountain"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-amountain:1.32.0--r44_0' :
        'quay.io/biocontainers/bioconductor-amountain:1.32.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_amountain_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_amountain_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_amountain_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(AMOUNTAIN)
    library(jsonlite)

    # --- Networksimulation [] ---
    # Key functions: networkSimulation
    ---------------------------------------------------------------------
    library(AMOUNTAIN)
    n = 100
    k = 20
    theta = 0.5
    # --- Qgraph [] ---
    # Key functions: qgraph
    ---------------------------------------------------------------------
    require(qgraph)
    pg <- qgraph(pp[[1]],groups=groupdesign,legend=TRUE)
    # --- Twolayernetworksimulation [] ---
    # Key functions: twolayernetworkSimulation
    ---------------------------------------------------------------------
    n1 = 100
    k1 = 20
    theta1 = 0.5
    n2 = 80
    # --- Qgraph [] ---
    # Key functions: qgraph
    ---------------------------------------------------------------------
    g <- qgraph(twolayernet,groups=groupdesign,legend=TRUE)
    # --- Networksimulation [] ---
    # Key functions: networkSimulation, moduleIdentificationGPFixSS
    ---------------------------------------------------------------------
    n = 100
    k = 20
    theta = 0.5
    pp <- networkSimulation(n,k,theta)
    # --- Persp [] ---
    # Key functions: persp
    ---------------------------------------------------------------------
    persp(Fscores,theta = 45,phi = 30,col = "gray",scale = FALSE,xlab = 'alpha',ylab = 'lambda',
          zlab = 'F-score',main = 'Fscores of identified module',box = TRUE)
    # --- Moduleidentificationgpfixsstwolayer [] ---
    # Key functions: moduleIdentificationGPFixSSTwolayer, intersect
    ---------------------------------------------------------------------
    ## network simulation is the same as before
    modres <- moduleIdentificationGPFixSSTwolayer(pp[[1]],pp[[2]],rep(1/n1,n1),pp2[[1]],pp2[[2]],rep(1/n2,n2),A)
    predictedid <- which(modres[[1]]!=0)
    recall <- length(intersect(predictedid,moduleid))/length(moduleid)
    # --- Multilayernetworksimulation [] ---
    # Key functions: multilayernetworkSimulation, moduleIdentificationGPFixSSMultilayer, intersect
    ---------------------------------------------------------------------
    ## network simulation
    n = 100
    k = 20
    L = 5

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_amountain_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_amountain_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_amountain_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_AMOUNTAIN:", paste0("    amountain: ", packageVersion("AMOUNTAIN"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_amountain_results.csv
    touch ${prefix}_amountain_output.rds
    echo "BIOC_AMOUNTAIN:" > versions.yml
    echo "    amountain: 0.0.0" >> versions.yml
    """
}


workflow BIOC_AMOUNTAIN_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_AMOUNTAIN(ch_input)

    emit:
    results  = BIOC_AMOUNTAIN.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_AMOUNTAIN.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_AMOUNTAIN.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_AMOUNTAIN.out.versions  // channel: path(versions.yml)
}
