#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: PhosR
// PhosR is a package for the comprenhensive analysis of phosphoproteomic data. There are two major com
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/PhosR/inst/doc/PhosR.R
// Upstream  : ClueR, GGally, annotate, calibrate, directPA
// Downstream: none
//
// Install: BiocManager::install("PhosR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PHOSR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-phosr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-phosr:1.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-phosr:1.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_phosr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_phosr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_phosr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GeneSymbol)
    library(Overrepresentation)
    library(PhosphoExperiment)
    library(RNGkind)
    library(RUVphospho)
    library(Residue)
    library(Sequence)
    library(Site)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: PhosphoExperiment
    ---------------------------------------------------------------------
    data("phospho_L6_ratio")
    ppe <- PhosphoExperiment(assays = list(Quantification = as.matrix(phospho.L6.ratio)))
    class(ppe)
    # --- Genesymbol [] ---
    # Key functions: GeneSymbol, Residue, Site
    ---------------------------------------------------------------------
    # --- Phosphoexperiment [] ---
    # Key functions: PhosphoExperiment
    ---------------------------------------------------------------------
    # --- Data [] ---
    # Key functions: data, class
    ---------------------------------------------------------------------
    data("phospho.cells.Ins.pe")
    ppe <- phospho.cells.Ins.pe
    class(ppe)
    # --- Selectgrps [] ---
    # Key functions: selectGrps
    ---------------------------------------------------------------------
    ppe_filtered <- selectGrps(ppe, grps, 0.5, n=1)
    dim(ppe_filtered)
    # --- Replicates [] ---
    # Key functions: replicates, selectGrps
    ---------------------------------------------------------------------
    # In cases where you have fewer replicates ( e.g.,triplicates), you may want to
    # select phosphosites quantified in 70% of replicates.
    ppe_filtered_v1 <- selectGrps(ppe, grps, 0.7, n=1)
    dim(ppe_filtered_v1)
    # --- Medianscaling [] ---
    # Key functions: medianScaling
    ---------------------------------------------------------------------
    ppe_imputed_scaled <- medianScaling(ppe_imputed, scale = FALSE, assay = "imputed")
    # --- Plotqc [] ---
    # Key functions: plotQC, assay, ggarrange
    ---------------------------------------------------------------------
    p1 = plotQC(SummarizedExperiment::assay(ppe_filtered,"Quantification"),
        labels=colnames(ppe_filtered),
        panel = "quantify", grps = grps)
    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    data("phospho_L6_ratio_pe")
    data("SPSs")
    ppe <- phospho.L6.ratio.pe
    ppe
    # --- Sum [] ---
    # Key functions: na, assay
    ---------------------------------------------------------------------
    sum(is.na(SummarizedExperiment::assay(ppe,"Quantification")))
    # --- Plotqc [] ---
    # Key functions: plotQC, assay, ggtitle
    ---------------------------------------------------------------------
    plotQC(SummarizedExperiment::assay(ppe,"Quantification"), panel = "dendrogram",
        grps=grps, labels = colnames(ppe)) +
        ggplot2::ggtitle("Before batch correction")
    # --- Which [] ---
    # Key functions: RUVphospho
    ---------------------------------------------------------------------
    # phosphoproteomics data normalisation and batch correction using RUV
    ctl = which(sites %in% SPSs)
    ppe = RUVphospho(ppe, M = design, k = 3, ctl = ctl)
    # --- Plotqc [] ---
    # Key functions: plotQC, assay, ggarrange
    ---------------------------------------------------------------------
    # plot after batch correction
    p1 = plotQC(SummarizedExperiment::assay(ppe, "Quantification"), grps=grps,
        labels = colnames(ppe), panel = "dendrogram" )
    # --- Plotqc [] ---
    # Key functions: plotQC, assay, ggtitle, ggarrange
    ---------------------------------------------------------------------
    # plot after batch correction
    p1 = plotQC(SummarizedExperiment::assay(ppe, "Quantification"), panel = "pca",
        grps=grps, labels = colnames(ppe)) +
        ggplot2::ggtitle("Before Batch correction")
    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    data("phospho_L6_ratio_pe")
    data("phospho.liver.Ins.TC.ratio.RUV.pe")
    data("phospho.cells.Ins.pe")
    ppe1 <- phospho.L6.ratio.pe

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_phosr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_phosr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_phosr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PHOSR:", paste0("    phosr: ", packageVersion("PhosR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_phosr_results.csv
    touch ${prefix}_phosr_output.rds
    echo "BIOC_PHOSR:" > versions.yml
    echo "    phosr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PHOSR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PHOSR(ch_input)

    emit:
    results  = BIOC_PHOSR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PHOSR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PHOSR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PHOSR.out.versions  // channel: path(versions.yml)
}
