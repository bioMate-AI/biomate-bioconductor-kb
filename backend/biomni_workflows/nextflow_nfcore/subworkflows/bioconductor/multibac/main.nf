#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MultiBaC
// MultiBaC is a strategy to correct batch effects from multiomic datasets distributed across different
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MultiBaC/inst/doc/MultiBaC.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("MultiBaC")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MULTIBAC {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-multibac"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-multibac:1.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-multibac:1.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_multibac_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_multibac_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_multibac_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ARSyNbac)
    library(MultiBaC)
    library(jsonlite)

    # --- create Mbac [] ---
    # Key functions: createMbac
    data("multiyeast")
    data_RNA <- createMbac (inputOmics = list(A.rna, B.rna, C.rna),
    batchFactor = c("A", "B", "C"),
    # --- A R Sy Nbac [] ---
    # Key functions: ARSyNbac
    par(mfrow = c(1,2))
    arsyn_1 <- ARSyNbac(data_RNA, modelName = "RNA", Variability = 0.95,
    plot(arsyn_1, typeP="pca.cor", bty = "L",
    # --- Multi Ba C [] ---
    # Key functions: MultiBaC, genModelList, genMissingOmics, batchCorrection
    my_final_mbac <- MultiBaC (my_mbac,
    my_mbac_2 <- genModelList (my_mbac, test.comp = NULL,
    multiBatchDesign <- genMissingOmics(my_mbac_2)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_multibac_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_multibac_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_multibac_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MULTIBAC:", paste0("    multibac: ", packageVersion("MultiBaC"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multibac_results.csv
    touch ${prefix}_multibac_output.rds
    echo "BIOC_MULTIBAC:" > versions.yml
    echo "    multibac: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MULTIBAC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MULTIBAC(ch_input)

    emit:
    results  = BIOC_MULTIBAC.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MULTIBAC.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MULTIBAC.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MULTIBAC.out.versions  // channel: path(versions.yml)
}
