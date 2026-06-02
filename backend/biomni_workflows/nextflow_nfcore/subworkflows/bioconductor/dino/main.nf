#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: Dino
// Dino normalizes single-cell, mRNA sequencing data to correct for technical variation, particularly s
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/Dino/inst/doc/Dino.R
// Upstream  : knitr, Seurat, Matrix, SingleCellExperiment, scran
// Downstream: none
//
// Install: BiocManager::install("Dino")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DINO {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-dino"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-dino:1.12.0--r44_0' :
        'quay.io/biocontainers/bioconductor-dino:1.12.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_dino_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_dino_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_dino_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Dino)
    library(Dino_SCE)
    library(FindNeighbors)
    library(FindVariableFeatures)
    library(RunPCA)
    library(ScaleData)
    library(SeuratFromDino)
    library(SingleCellExperiment)
    library(jsonlite)

    # --- Seurat Integration [] ---
    # Key functions: SeuratFromDino
    pbmcSmall_Seurat = SeuratFromDino(pbmcSmall_Norm, doNorm = FALSE)
    pbmcSmall_Seurat = Seurat::FindVariableFeatures(pbmcSmall_Seurat,
                                                    selection.method = "mvp")
    pbmcSmall_Seurat = Seurat::ScaleData(pbmcSmall_Seurat,
                                         features = rownames(pbmcSmall_Norm))


    # --- SingleCellExperiment Integration [] ---
    # Key functions: Dino_SCE
    pbmc_SCE = SingleCellExperiment::SingleCellExperiment(
        assays = list("counts" = pbmcSmall)
    )
    pbmc_SCE = Dino_SCE(pbmc_SCE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_dino_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_dino_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_dino_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DINO:", paste0("    dino: ", packageVersion("Dino"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_dino_results.csv
    touch ${prefix}_dino_output.rds
    echo "BIOC_DINO:" > versions.yml
    echo "    dino: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DINO_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DINO(ch_input)

    emit:
    results  = BIOC_DINO.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DINO.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DINO.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DINO.out.versions  // channel: path(versions.yml)
}
