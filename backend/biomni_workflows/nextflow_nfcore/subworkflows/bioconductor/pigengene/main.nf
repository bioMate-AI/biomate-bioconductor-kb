#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: Pigengene
// Pigengene package provides an efficient way to infer biological signatures from gene expression prof
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/Pigengene/inst/doc/Pigengene_inference.R
// Upstream  : bnlearn
// Downstream: none
//
// Install: BiocManager::install("Pigengene")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PIGENGENE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-pigengene"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-pigengene:1.32.0--r44_0' :
        'quay.io/biocontainers/bioconductor-pigengene:1.32.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_pigengene_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_pigengene_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_pigengene_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Pigengene)
    library(jsonlite)

    # --- rbind [] ---
    # Key functions: rbind
    library(Pigengene)
    data(aml)
    data(mds)
    # --- balance [] ---
    # Key functions: balance
    wData <- balance(Data=DataI, Labels=LabelsI, verbose=1)$balanced
    # --- children [] ---
    # Key functions: children
    fit <- bn.fit(x=BN, data=learnt$consensus1$Data, method="bayes", iss=10)
    selectedFeatures <- children("Disease", x=BN)
    print(fit[[selectedFeatures[1]]])
    # --- predict [] ---
    # Key functions: predict
    l2 <- predict(object=fit, node="Disease", data=learnt$consensus1$Data, method="bayes-lw")
    table(LabelsI, l2)
    # --- set Names [] ---
    # Key functions: setNames, split
    usedFeatures <- get.used.features(c5Tree=treeRes$c5Trees[["17"]])
    moduleMembers <- setNames(paste0("ME", wgRes$modules),
    nm=sub("_[^_]+$", "", names(wgRes$modules)))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_pigengene_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_pigengene_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_pigengene_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PIGENGENE:", paste0("    pigengene: ", packageVersion("Pigengene"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pigengene_results.csv
    touch ${prefix}_pigengene_output.rds
    echo "BIOC_PIGENGENE:" > versions.yml
    echo "    pigengene: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PIGENGENE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PIGENGENE(ch_input)

    emit:
    results  = BIOC_PIGENGENE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PIGENGENE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PIGENGENE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PIGENGENE.out.versions  // channel: path(versions.yml)
}
