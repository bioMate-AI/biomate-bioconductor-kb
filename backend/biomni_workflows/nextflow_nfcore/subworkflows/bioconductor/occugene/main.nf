#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: occugene
// Statistical tools for building random mutagenesis libraries for prokaryotes. The package has functio
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/occugene/inst/doc/occugene.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("occugene")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_OCCUGENE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-occugene"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-occugene:1.66.0--r44_0' :
        'quay.io/biocontainers/bioconductor-occugene:1.66.0--r44_0'}"

    input:
    tuple val(meta), path(plot_object)

    output:
    tuple val(meta), path("${meta.id}_occugene_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_occugene_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_occugene_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(occugene)
    library(jsonlite)

    # --- Momments [] ---
    # Key functions: eMult, varMult
    library("occugene")
    n <- 60
    p <- c(seq(10,1,-1),seq(10,1,-1),18)/124
    p <- p/sum(p)
    eMult(n,p)
    # --- Approx Momments [] ---
    # Key functions: eMult, varMult
    eMult(n,p,iter=100,seed=4)
    varMult(n,p,iter=100,seed=4)
    # --- Et [] ---
    # Key functions: etDelta
    orf <- cbind(a.data$first,a.data$last)
    clone <- experiment$position
    etDelta(10,orf,clone)
    # --- Wj Next [] ---
    # Key functions: fFit, unbiasDelta0
    orf <- cbind(a.data$first,a.data$last)
    clone <- experiment$position
    fFit(orf,clone,FALSE)
    unbiasDelta0(10,orf,clone,iter=10,seed=4,alpha=0.05,TR=F)
    # --- Number Essential Will [] ---
    # Key functions: unbiasB0
    unbiasB0(orf,clone,iter=10,seed=4,alpha=0.05,TR=F)
    # --- Conversion [] ---
    # Key functions: occup2Negenes
    newOrf <- occup2Negenes(orf,clone)
    print(newOrf)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_occugene_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_occugene_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_occugene_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_OCCUGENE:", paste0("    occugene: ", packageVersion("occugene"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_occugene_results.csv
    touch ${prefix}_occugene_output.rds
    echo "BIOC_OCCUGENE:" > versions.yml
    echo "    occugene: 0.0.0" >> versions.yml
    """
}


workflow BIOC_OCCUGENE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(plot_object) ]

    main:
    BIOC_OCCUGENE(ch_input)

    emit:
    results  = BIOC_OCCUGENE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_OCCUGENE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_OCCUGENE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_OCCUGENE.out.versions  // channel: path(versions.yml)
}
