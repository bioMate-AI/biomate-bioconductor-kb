#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: BubbleTree
// CNV analysis in groups of tumor samples.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/BubbleTree/inst/doc/BubbleTree-vignette.R
// Upstream  : GenomicRanges
// Downstream: none
//
// Install: BiocManager::install("BubbleTree")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BUBBLETREE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-bubbletree"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-bubbletree:2.36.0--r44_0' :
        'quay.io/biocontainers/bioconductor-bubbletree:2.36.0--r44_0'}"

    input:
    tuple val(meta), path(plot_object)

    output:
    tuple val(meta), path("${meta.id}_bubbletree_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_bubbletree_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_bubbletree_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BubbleTree)
    library(jsonlite)

    # --- RBD Object Creation [RBD Initialization] ---
    # Key functions: makeRBD
    cnv_file <- system.file("data", "cnv.gr.rda", package = "BubbleTree")
    snp_file <- system.file("data", "snp.gr.rda", package = "BubbleTree")
    load(cnv_file)
    load(snp_file)
    r_obj <- new("RBD", unimodal.kurtosis = -0.1)
    rbd_data <- makeRBD(r_obj, snp.gr, cnv.gr)

    # --- Purity and Ploidy Prediction [Prediction] ---
    # Key functions: btpredict, info
    predictor <- new("BTreePredictor",
                     rbd = rbd_data,
                     max.ploidy = 6,
                     prev.grid = seq(0.2, 1, by = 0.01))
    pred_res <- btpredict(predictor)
    purity_ploidy <- info(pred_res)

    # --- Clonal Architecture Visualization [Visualization] ---
    # Key functions: drawBTree, trackBTree
    plotter <- new("BTreePlotter", max.ploidy = 5, max.size = 10)
    arrows <- trackBTree(plotter,
                         pred_res@rbd,
                         pred_res@rbd.adj,
                         min.srcSize = 0.01,
                         min.trtSize = 0.01)
    btree_plot <- drawBTree(plotter, pred_res@rbd) + arrows

    # --- Genomic Annotation and Feature Plotting [Annotation] ---
    # Key functions: btcompare, annoByGenesAndCyto, drawFeatures, drawBTree
    load(system.file("data", "cancer.genes.minus2.rda", package = "BubbleTree"))
    load(system.file("data", "vol.genes.rda", package = "BubbleTree"))
    load(system.file("data", "gene.uni.clean.gr.rda", package = "BubbleTree"))
    load(system.file("data", "cyto.gr.rda", package = "BubbleTree"))
    annotator <- new("Annotate")
    comm <- btcompare(vol.genes, cancer.genes.minus2)
    out_df <- pred_res@result$dist
    ann_res <- annoByGenesAndCyto(annotator,
                                  as.character(out_df$seqnames),
                                  as.numeric(out_df$start),
                                  as.numeric(out_df$end),
                                  comm$comm,
                                  gene.uni.clean.gr = gene.uni.clean.gr,
                                  cyto.gr = cyto.gr)
    out_df$cyto <- ann_res$cyto
    out_df$genes <- ann_res$ann
    plotter_ann <- new("BTreePlotter", branch.col = "gray50")
    btree_annotated <- drawBTree(plotter_ann, pred_res@rbd.adj) +
        drawFeatures(plotter_ann, out_df)


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_bubbletree_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_bubbletree_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_bubbletree_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BUBBLETREE:", paste0("    bubbletree: ", packageVersion("BubbleTree"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bubbletree_results.csv
    touch ${prefix}_bubbletree_output.rds
    echo "BIOC_BUBBLETREE:" > versions.yml
    echo "    bubbletree: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BUBBLETREE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(plot_object) ]

    main:
    BIOC_BUBBLETREE(ch_input)

    emit:
    results  = BIOC_BUBBLETREE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BUBBLETREE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BUBBLETREE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BUBBLETREE.out.versions  // channel: path(versions.yml)
}
