#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: miRLAB
// Provide tools exploring miRNA-mRNA relationships, including popular miRNA target prediction methods,
//
// Source : https://bioconductor.org/packages/3.20/bioc/https://bioconductor.org/packages/3.20/bioc/vignettes/miRLAB/inst/doc/miRLAB-vignette.html
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("miRLAB")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MIRLAB {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mirlab"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-mirlab:1.36.0--r44_0' :
        'quay.io/biocontainers/bioconductor-mirlab:1.36.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_mirlab_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mirlab_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mirlab_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Extopk)
    library(IDA)
    library(Lasso)
    library(MI)
    library(Pearson)
    library(Read)
    library(Validation)
    library(jsonlite)

    # --- Code Block 1 [] ---
    # Key functions: Pearson, MI, IDA, Lasso
    library(miRLAB)
    dataset=system.file("extdata", "EMT35.csv", package="miRLAB")
    cause=1:35 #column 1:35 are miRNAs
    effect=36:1189 #column 36:1189 are mRNAs
    #predict miRNA targets using Pearson correlation
    # --- Code Block 2 [] ---
    # Key functions: Pearson, bRank, Validation
    library(miRLAB)
    #validate the results of the top100 targets of each miRNA predicted
    #by the four methods
    dataset=system.file("extdata", "ToyEMT.csv", package="miRLAB")
    pearson=Pearson(dataset, 1:3, 4:18)
    # --- Code Block 3 [] ---
    # Key functions: Pearson, Extopk, Validation
    library(miRLAB)
    #validate the results of the top100 targets of each miRNA predicted
    #by the four methods
    dataset=system.file("extdata", "ToyEMT.csv", package="miRLAB")
    EMTresults=Pearson(dataset, 1:3, 4:18)
    # --- Code Block 4 [] ---
    # Key functions: Read
    library(miRLAB)
    dataset=system.file("extdata", "ToyEMT.csv", package="miRLAB")
    dataset=Read(dataset)
    dataset[1:5,1:7]
    # --- Code Block 5 [] ---
    # Key functions: Read
    library(miRLAB)
    groundtruth=system.file("extdata", "Toygroundtruth.csv", package="miRLAB")
    groundtruth=Read(groundtruth)
    groundtruth[1:5,]

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_mirlab_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_mirlab_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_mirlab_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MIRLAB:", paste0("    mirlab: ", packageVersion("miRLAB"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mirlab_results.csv
    touch ${prefix}_mirlab_output.rds
    echo "BIOC_MIRLAB:" > versions.yml
    echo "    mirlab: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MIRLAB_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MIRLAB(ch_input)

    emit:
    results  = BIOC_MIRLAB.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MIRLAB.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MIRLAB.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MIRLAB.out.versions  // channel: path(versions.yml)
}
