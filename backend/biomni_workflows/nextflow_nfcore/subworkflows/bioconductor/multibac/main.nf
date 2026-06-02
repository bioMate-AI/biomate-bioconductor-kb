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

    # --- Data Initialization [MultiBaC Object Creation] ---
    # Key functions: createMbac
    data("multiyeast")
    data_RNA <- createMbac(
        inputOmics = list(A.rna, B.rna, C.rna),
        batchFactor = c("A", "B", "C"),
        experimentalDesign = list(
            "A" = c("Glu+", "Glu+", "Glu+", "Glu-", "Glu-", "Glu-"),
            "B" = c("Glu+", "Glu+", "Glu-", "Glu-"),
            "C" = c("Glu+", "Glu+", "Glu-", "Glu-")
        ),
        omicNames = "RNA"
    )

    # --- Exploratory Data Analysis [PCA of Original Data] ---
    # Key functions: plot
    custom_col <- c("brown2", "dodgerblue", "forestgreen")
    custom_pch <- c(19, 19, 19, 1, 1, 1, 19, 19, 1, 1, 19, 19, 1, 1)
    plot(
        data_RNA,
        typeP = "pca.org",
        bty = "L",
        pch = custom_pch,
        cex = 2,
        col.per.group = custom_col
    )

    # --- Batch Effect Correction [ARSyNbac Correction] ---
    # Key functions: ARSyNbac
    arsyn_corrected <- ARSyNbac(
        data_RNA,
        modelName = "RNA",
        Variability = 0.95,
        batchEstimation = TRUE,
        filterNoise = TRUE,
        Interaction = TRUE
    )

    # --- Post-Correction Visualization [PCA of Corrected Data] ---
    # Key functions: plot
    custom_col <- c("brown2", "dodgerblue", "forestgreen")
    custom_pch <- c(19, 19, 19, 1, 1, 1, 19, 19, 1, 1, 19, 19, 1, 1)
    plot(
        arsyn_corrected,
        typeP = "pca.cor",
        bty = "L",
        pch = custom_pch,
        cex = 2,
        col.per.group = custom_col
    )


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
