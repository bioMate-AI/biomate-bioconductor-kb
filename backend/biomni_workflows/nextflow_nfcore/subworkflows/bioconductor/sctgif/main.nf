#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: scTGIF
// scTGIF connects the cells and the related gene functions without cell type label.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/scTGIF/inst/doc/scTGIF.R
// Upstream  : GSEABase, SingleCellExperiment, msigdbr
// Downstream: none
//
// Install: BiocManager::install("scTGIF")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SCTGIF {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-sctgif"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-sctgif:1.20.0--r44_0' :
        'quay.io/biocontainers/bioconductor-sctgif:1.20.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_sctgif_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_sctgif_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_sctgif_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GeneSet)
    library(SingleCellExperiment)
    library(jsonlite)

    # --- Gene Set [] ---
    # Key functions: GeneSet
    m_df = msigdbr(species = "Mus musculus",
    category = "H")[, c("gs_name", "entrez_gene")]
    hallmark = unique(m_df$gs_name)
    # --- Create SingleCellExperiment object [] ---
    # Key functions: SingleCellExperiment, reducedDims
    sce <- SingleCellExperiment(assays = list(counts = DistalLungEpithelium))
    reducedDims(sce) <- SimpleList(PCA=pca.DistalLungEpithelium)
    # --- col Sums [] ---
    # Key functions: colSums, normcounts
    CPMED <- function(input){
    libsize <- colSums(input)
    median(libsize) * t(t(input) / libsize)
    # --- setting T G I F [] ---
    # Key functions: settingTGIF
    settingTGIF(sce, gmt, reducedDimNames="PCA", assayNames="normcounts")
    # --- calc T G I F [] ---
    # Key functions: calcTGIF
    calcTGIF(sce, ndim=3)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_sctgif_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_sctgif_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_sctgif_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SCTGIF:", paste0("    sctgif: ", packageVersion("scTGIF"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sctgif_results.csv
    touch ${prefix}_sctgif_output.rds
    echo "BIOC_SCTGIF:" > versions.yml
    echo "    sctgif: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SCTGIF_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SCTGIF(ch_input)

    emit:
    results  = BIOC_SCTGIF.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SCTGIF.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SCTGIF.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SCTGIF.out.versions  // channel: path(versions.yml)
}
