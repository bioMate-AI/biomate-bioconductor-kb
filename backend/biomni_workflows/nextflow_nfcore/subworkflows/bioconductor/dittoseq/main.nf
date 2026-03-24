#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: dittoSeq
// A universal, user friendly, single-cell and bulk RNA sequencing visualization toolkit that allows hi
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/dittoSeq/inst/doc/dittoSeq.R
// Upstream  : BiocStyle, SummarizedExperiment, bluster, scRNAseq, scater
// Downstream: none
//
// Install: BiocManager::install("dittoSeq")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DITTOSEQ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-dittoseq"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-dittoseq:1.18.0--r44_0' :
        'quay.io/biocontainers/bioconductor-dittoseq:1.18.0--r44_0'}"

    input:
    tuple val(meta), path(seurat_object)

    output:
    tuple val(meta), path("${meta.id}_dittoseq_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_dittoseq_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_dittoseq_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BaronPancreasData)
    library(FindMarkers)
    library(Idents)
    library(Seurat)
    library(SummarizedExperiment)
    library(jsonlite)

    # --- Baronpancreasdata [] ---
    # Key functions: BaronPancreasData
    ---------------------------------------------------------------------
    ## Download Data
    library(scRNAseq)
    sce <- BaronPancreasData()
    # Trim to only 5 of the cell types for simplicity of vignette
    # --- Lognormcounts [] ---
    # Key functions: logNormCounts, modelGeneVar, getTopHVGs, runPCA, runUMAP, clusterCells
    ---------------------------------------------------------------------
    ## Some Quick Pre-processing
    # Normalization.
    library(scater)
    sce <- logNormCounts(sce)
    # --- Dittodimplot [] ---
    # Key functions: dittoDimPlot, dittoPlot, dittoBarPlot
    ---------------------------------------------------------------------
    library(dittoSeq)
    dittoDimPlot(sce, "donor")
    dittoPlot(sce, "ENO1", group.by = "label")
    dittoBarPlot(sce, "label", group.by = "donor")
    # --- Matrix [] ---
    # Key functions: rpois
    ---------------------------------------------------------------------
    # First, we'll just make some mock expression and conditions data
    exp <- matrix(rpois(20000, 5), ncol=20)
    colnames(exp) <- paste0("donor", seq_len(ncol(exp)))
    rownames(exp) <- paste0("gene", seq_len(nrow(exp)))
    # --- Summarizedexperiment [] ---
    # Key functions: SummarizedExperiment, frame
    ---------------------------------------------------------------------
    library(SummarizedExperiment)
    bulkSE <- SummarizedExperiment(
        assays = list(counts = exp,
                 logcounts = logexp),
    # --- Importdittobulk [] ---
    # Key functions: importDittoBulk, frame
    ---------------------------------------------------------------------
    # dittoSeq import which allows
    bulkSCE <- importDittoBulk(
        # x can be a DGEList, a DESeqDataSet, a SummarizedExperiment,
        #   or a list of data matrices
    # --- Metadata [] ---
    # Key functions: metadata, reductions, addDimReduction
    ---------------------------------------------------------------------
    # Add metadata (metadata can alternatively be added in this way)
    bulkSCE$conditions <- conditions
    bulkSCE$sex <- sex
    # Add dimensionality reductions (can alternatively be added this way)
    # --- Dittodimplot [] ---
    # Key functions: dittoDimPlot, dittoBarPlot, dittoBoxPlot, dittoHeatmap, getGenes
    ---------------------------------------------------------------------
    library(dittoSeq)
    dittoDimPlot(bulkSCE, "sex", size = 3, do.ellipse = TRUE)
    dittoBarPlot(bulkSCE, "sex", group.by = "conditions")
    dittoBoxPlot(bulkSCE, "gene1", group.by = "sex")
    # --- Getmetas [] ---
    # Key functions: getMetas, isMeta, meta, metaLevels
    ---------------------------------------------------------------------
    # Retrieve all metadata slot names
    getMetas(sce)
    # Query for the presence of a metadata slot
    isMeta("nCount_RNA", sce)
    # --- Getgenes [] ---
    # Key functions: getGenes, gene, isGene
    ---------------------------------------------------------------------
    # Retrieve all gene names
    getGenes(sce)[1:10]
    # Query for the presence of a gene(s)
    isGene("CD3E", sce)
    # --- Getreductions [] ---
    # Key functions: getReductions
    ---------------------------------------------------------------------
    # Retrieve all dimensionality reductions
    getReductions(sce)
    # --- Isbulk [] ---
    # Key functions: isBulk, setBulk
    ---------------------------------------------------------------------
    # Getter
    isBulk(sce)
    isBulk(bulkSCE)
    # Setter
    # --- Dittodimplot [] ---
    # Key functions: dittoDimPlot
    ---------------------------------------------------------------------
    dittoDimPlot(sce, "cluster",
                 do.label = TRUE,
                 labels.repel = FALSE,
                 add.trajectory.lineages = list(
    # --- Dittoplot [] ---
    # Key functions: dittoPlot
    ---------------------------------------------------------------------
    dittoPlot(sce, "ENO1", group.by = "label",
        plots = c("jitter", "vlnplot", "boxplot"), # <- order matters
        # change the color and size of jitter points
        jitter.color = "blue", jitter.size = 0.5,
    # --- Dittoheatmap [] ---
    # Key functions: dittoHeatmap
    ---------------------------------------------------------------------
    # Add annotations
    dittoHeatmap(sce, genes,
        annot.by = c("label", "donor"),
        scaled.to.max = TRUE,

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_dittoseq_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_dittoseq_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_dittoseq_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DITTOSEQ:", paste0("    dittoseq: ", packageVersion("dittoSeq"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_dittoseq_results.csv
    touch ${prefix}_dittoseq_output.rds
    echo "BIOC_DITTOSEQ:" > versions.yml
    echo "    dittoseq: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DITTOSEQ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(seurat_object) ]

    main:
    BIOC_DITTOSEQ(ch_input)

    emit:
    results  = BIOC_DITTOSEQ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DITTOSEQ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DITTOSEQ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DITTOSEQ.out.versions  // channel: path(versions.yml)
}
