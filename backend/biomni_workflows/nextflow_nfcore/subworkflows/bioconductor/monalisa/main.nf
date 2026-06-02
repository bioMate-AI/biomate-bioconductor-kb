#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: monaLisa
// Useful functions to work with sequence motifs in the analysis of genomics data. These include method
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/monaLisa/inst/doc/selecting_motifs_with_randLassoStabSel.R
// Upstream  : Biostrings, ComplexHeatmap, JASPAR2020, SummarizedExperiment, TFBSTools
// Downstream: none
//
// Install: BiocManager::install("monaLisa")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MONALISA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-monalisa"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-monalisa:1.12.0--r44_0' :
        'quay.io/biocontainers/bioconductor-monalisa:1.12.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_monalisa_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_monalisa_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_monalisa_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(monaLisa)
    library(HeatmapAnnotation)
    library(RNGkind)
    library(jsonlite)

    # --- Data Loading and Motif Preparation [monaLisa] ---
    # Key functions: getMatrixSet
    gr_path <- system.file("extdata", "atac_liver_vs_lung.rds",
                           package = "monaLisa")
    gr <- readRDS(gr_path)
    pfms <- JASPAR2020::getMatrixSet(
        JASPAR2020::JASPAR2020,
        list(matrixtype = "PFM", tax_group = "vertebrates")
    )
    pwms <- TFBSTools::toPWM(pfms[1:100])

    # --- Motif Search and Hit Detection [monaLisa] ---
    # Key functions: findMotifHits
    peakSeq <- Biostrings::getSeq(
        BSgenome.Mmusculus.UCSC.mm10::BSgenome.Mmusculus.UCSC.mm10,
        gr
    )
    hits <- findMotifHits(
        query = pwms,
        subject = peakSeq,
        min.score = 10.0,
        BPPARAM = BiocParallel::SerialParam()
    )

    # --- Predictor Matrix Preparation [monaLisa] ---
    # Key functions: findMotifHits
    TFBSmatrix <- unclass(table(
        factor(seqnames(hits), levels = seqlevels(hits)),
        factor(hits$pwmname, levels = TFBSTools::name(pwms))
    ))
    TFBSmatrix <- TFBSmatrix[, colSums(TFBSmatrix) > 0]
    fMono <- Biostrings::oligonucleotideFrequency(
        peakSeq, width = 1L, as.prob = TRUE
    )
    fDi <- Biostrings::oligonucleotideFrequency(
        peakSeq, width = 2L, as.prob = TRUE
    )
    fracGC <- fMono[, "G"] + fMono[, "C"]
    oeCpG <- (fDi[, "CG"] + 0.01) / (fMono[, "G"] * fMono[, "C"] + 0.01)
    TFBSmatrix <- cbind(fracGC, oeCpG, TFBSmatrix)

    # --- Stability Selection [monaLisa] ---
    # Key functions: randLassoStabSel
    se <- randLassoStabSel(
        x = TFBSmatrix,
        y = gr$logFC_liver_vs_lung,
        cutoff = 0.8
    )
    selected_tfs <- colnames(se)[se$selected]

    # --- Stability and Selection Plotting [monaLisa] ---
    # Key functions: plotStabilityPaths, plotSelectionProb
    plotStabilityPaths(se)
    plotSelectionProb(
        se,
        directional = TRUE,
        col = c("red", "blue"),
        main = "TF Selection Probabilities"
    )
    selected_features <- colnames(se)[se$selected]

    # --- Motif Correlation and Logo Visualization [monaLisa] ---
    # Key functions: seqLogoGrob, annoSeqlogo
    sel <- colnames(se)[se$selected]
    se_sub <- se[, sel]
    se_sub <- se_sub[, !colnames(se_sub) %in% c("oeCpG", "fracGC")]
    TFBSmatrixCorSel <- cor(TFBSmatrix[, colnames(se_sub)], method = "pearson")
    pfmsSel <- pfms[match(colnames(TFBSmatrixCorSel), TFBSTools::name(pfms))]
    maxwidth <- max(sapply(TFBSTools::Matrix(pfmsSel), ncol))
    seqlogoGrobs <- lapply(pfmsSel, seqLogoGrob, xmax = maxwidth)
    hmSeqlogo <- ComplexHeatmap::rowAnnotation(
        logo = annoSeqlogo(seqlogoGrobs, which = "row"),
        annotation_width = grid::unit(2, "inch"),
        show_annotation_name = FALSE
    )


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_monalisa_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_monalisa_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_monalisa_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MONALISA:", paste0("    monalisa: ", packageVersion("monaLisa"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_monalisa_results.csv
    touch ${prefix}_monalisa_output.rds
    echo "BIOC_MONALISA:" > versions.yml
    echo "    monalisa: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MONALISA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MONALISA(ch_input)

    emit:
    results  = BIOC_MONALISA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MONALISA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MONALISA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MONALISA.out.versions  // channel: path(versions.yml)
}
