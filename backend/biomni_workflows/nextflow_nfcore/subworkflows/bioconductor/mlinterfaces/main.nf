#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MLInterfaces
// This package provides uniform interfaces to machine learning code for data in R and Bioconductor con
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MLInterfaces/inst/doc/MLint_devel.R
// Upstream  : ALL, MASS, cluster, keggorthology, lattice
// Downstream: pRoloc, SigCheck, dGAselID, nlcv
//
// Install: BiocManager::install("MLInterfaces")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MLINTERFACES {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mlinterfaces"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-mlinterfaces:1.86.0--r44_0' :
        'quay.io/biocontainers/bioconductor-mlinterfaces:1.86.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_mlinterfaces_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mlinterfaces_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mlinterfaces_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(RObject)
    library(jsonlite)

    # --- knn I [] ---
    # Key functions: knnI
    knnI(k=3, l=2)@converter
    # --- R Object [] ---
    # Key functions: RObject
    library(MASS)
    data(crabs)
    kp = sample(1:200, size=120)
    # --- confu Mat [] ---
    # Key functions: confuMat, RObject
    adaI = makeLearnerSchema("ada", "ada", standardMLIConverter )
    arun = MLearn(sp~CL+RW, data=crabs, adaI, kp )
    confuMat(arun)
    # --- confu Mat [] ---
    # Key functions: confuMat
    set.seed(1234)
    gbrun = MLearn(sp~CL+RW+FL+CW+BD, data=crabs, BgbmI(n.trees.pred=25000,thresh=.5), kp, n.trees=25000, distribution="bernoulli", verbose=FALSE )
    confuMat(gbrun)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_mlinterfaces_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_mlinterfaces_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_mlinterfaces_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MLINTERFACES:", paste0("    mlinterfaces: ", packageVersion("MLInterfaces"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mlinterfaces_results.csv
    touch ${prefix}_mlinterfaces_output.rds
    echo "BIOC_MLINTERFACES:" > versions.yml
    echo "    mlinterfaces: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MLINTERFACES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MLINTERFACES(ch_input)

    emit:
    results  = BIOC_MLINTERFACES.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MLINTERFACES.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MLINTERFACES.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MLINTERFACES.out.versions  // channel: path(versions.yml)
}
