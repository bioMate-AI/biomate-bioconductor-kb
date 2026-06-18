#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: monalisa — randomized_lasso_stability_selection
// Identify transcription factor motifs that explain continuous experimental measurements using a regression-based approach with stability selection.
// Input: atac_peaks.bed, accessibility_changes.tsv, motifs.jaspar
// Container: quay.io/biocontainers/bioconductor-monalisa:1.16.0--r45hdfd78af_0
// R packages: BSgenome.Mmusculus.UCSC.mm10, BiocParallel, Biostrings, ComplexHeatmap, JASPAR2020, SummarizedExperiment, TFBSTools, circlize, monaLisa, rtracklayer
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: heatmap (ComplexHeatmap), heatmap

nextflow.enable.dsl = 2

process BIOC_MONALISA_RANDOMIZED_LASSO_STABILITY_SELECTION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-monalisa:1.16.0--r45hdfd78af_0"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("BSgenome.Mmusculus.UCSC.mm10", "BiocParallel", "Biostrings", "ComplexHeatmap", "JASPAR2020", "SummarizedExperiment", "TFBSTools", "circlize", "monaLisa", "rtracklayer")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
    }

    # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
    for (.bm_d in list.files(".", full.names = TRUE)) {
      if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
        for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
          if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
        }
      }
    }
    
    # Load required libraries
    library(monaLisa)
    library(JASPAR2020)
    library(TFBSTools)
    library(BSgenome.Mmusculus.UCSC.mm10)
    library(Biostrings)
    library(SummarizedExperiment)
    library(ComplexHeatmap)
    library(circlize)
    library(rtracklayer)
    library(BiocParallel)
    
    # --- Load genomic regions and response vector from user input ---
    message("Loading genomic regions and accessibility changes...")
    gr <- rtracklayer::import("atac_peaks.bed", format = "bed")
    acc <- read.delim("accessibility_changes.tsv", header = TRUE, stringsAsFactors = FALSE)
    
    # Match accessibility changes to genomic ranges
    if ("name" %in% colnames(acc) && !is.null(gr\$name)) {
      idx <- match(gr\$name, acc\$name)
      acc_matched <- acc[idx, ]
    } else {
      acc_matched <- acc
    }
    
    if ("logFC_liver_vs_lung" %in% colnames(acc_matched)) {
      gr\$logFC_liver_vs_lung <- acc_matched\$logFC_liver_vs_lung
    } else if ("logFC" %in% colnames(acc_matched)) {
      gr\$logFC_liver_vs_lung <- acc_matched\$logFC
    } else {
      # Fallback to the first numeric column
      num_cols <- sapply(acc_matched, is.numeric)
      if (any(num_cols)) {
        gr\$logFC_liver_vs_lung <- acc_matched[[which(num_cols)[1]]]
      } else {
        stop("No numeric column found in accessibility_changes.tsv to use as logFC!")
      }
    }
    
    # --- Scan regions for motif hits using findMotifHits to build ---
    message("Loading and processing motifs...")
    pfms <- TFBSTools::readJASPARMatrix("motifs.jaspar", matrixClass = "PFM")
    
    # Randomly sample up to 300 PFMs for illustration/runtime purposes
    set.seed(4563)
    pfms <- pfms[sample(length(pfms), size = min(300, length(pfms)))]
    pwms <- toPWM(pfms)
    
    message("Scanning sequences for motif hits...")
    peakSeq <- getSeq(BSgenome.Mmusculus.UCSC.mm10, gr)
    suppressWarnings({
      hits <- findMotifHits(query = pwms, subject = peakSeq, min.score = 10.0, BPPARAM = BiocParallel::SerialParam())
    })
    
    TFBSmatrix <- unclass(table(factor(seqnames(hits), levels = seqlevels(hits)), factor(hits\$pwmname, levels = name(pwms))))
    zero_TF <- colSums(TFBSmatrix) == 0
    TFBSmatrix <- TFBSmatrix[, !zero_TF, drop = FALSE]
    
    # --- Calculate additional sequence composition predictors and ---
    message("Calculating sequence composition predictors...")
    fMono <- oligonucleotideFrequency(peakSeq, width = 1L, as.prob = TRUE)
    fDi <- oligonucleotideFrequency(peakSeq, width = 2L, as.prob = TRUE)
    fracGC <- fMono[, "G"] + fMono[, "C"]
    oeCpG <- (fDi[, "CG"] + 0.01) / (fMono[, "G"] * fMono[, "C"] + 0.01)
    TFBSmatrix <- cbind(fracGC, oeCpG, TFBSmatrix)
    
    # --- Run randomized Lasso stability selection using ---
    message("Running randomized Lasso stability selection...")
    set.seed(123)
    se <- randLassoStabSel(x = TFBSmatrix, y = gr\$logFC_liver_vs_lung, cutoff = 0.8)
    
    # Save the SummarizedExperiment object
    saveRDS(se, "stability_selection_results.rds")
    
    # --- Plot stability paths using plotStabilityPaths ---
    message("Generating stability path plots...")
    pdf("stability_paths.pdf", width = 8, height = 6)
    plotStabilityPaths(se)
    dev.off()
    
    pdf("stability_paths_labeled.pdf", width = 10, height = 8)
    set.seed(123)
    plotStabilityPaths(se, labelPaths = TRUE)
    dev.off()
    
    # --- Plot selection probabilities using plotSelectionProb ---
    message("Generating selection probability plot...")
    pdf("selection_probabilities.pdf", width = 8, height = 6)
    plotSelectionProb(se, directional = TRUE, ylimext = 0.5)
    dev.off()
    
    # --- Visualize correlation structure of selected motifs using ---
    sel <- colnames(se)[se\$selected]
    
    if (length(sel) > 0) {
      message("Saving selected TFs to CSV...")
      selected_df <- data.frame(
        TF = sel,
        selProb = se\$selProb[sel],
        selAUC = se\$selAUC[sel],
        stringsAsFactors = FALSE
      )
      write.csv(selected_df, "selected_tfs.csv", row.names = FALSE)
    
      se_sub <- se[, sel]
      excl <- colnames(se_sub) %in% c("oeCpG", "fracGC")
      se_sub <- se_sub[, !excl]
    
      if (ncol(se_sub) > 0) {
        message("Generating correlation heatmap of selected TFs...")
        TFBSmatrixCorSel <- cor(TFBSmatrix[, colnames(se_sub), drop = FALSE], method = "pearson")
        pfmsSel <- pfms[match(colnames(TFBSmatrixCorSel), name(pfms))]
        maxwidth <- max(sapply(TFBSTools::Matrix(pfmsSel), ncol))
        seqlogoGrobs <- lapply(pfmsSel, seqLogoGrob, xmax = maxwidth)
        hmSeqlogo <- rowAnnotation(logo = annoSeqlogo(seqlogoGrobs, which = "row"), annotation_width = unit(2, "inch"), show_annotation_name = FALSE )
        colAnn <- HeatmapAnnotation(AUC = se_sub\$selAUC, selProb = se_sub\$selProb, show_legend = TRUE, show_annotation_name = TRUE, col = list( AUC = colorRamp2(c(0, 1), c("white", "brown")), selProb = colorRamp2(c(0, 1), c("white", "steelblue"))) )
        
        pdf("selected_tf_correlation_heatmap.pdf", width = 10, height = 10)
        draw(Heatmap(TFBSmatrixCorSel, show_row_names = TRUE, show_column_names = TRUE, name = "Pear. Cor.", column_title = "Selected TFs", col = colorRamp2(c(-1, 0, 1), c("blue", "white", "red")), right_annotation = hmSeqlogo, top_annotation = colAnn))
        dev.off()
      } else {
        message("No TF motifs left for heatmap after excluding GC and CpG predictors.")
      }
    } else {
      message("No TFs were selected by stability selection.")
    }
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_MONALISA_RANDOMIZED_LASSO_STABILITY_SELECTION":',
        paste0('        monalisa: ', as.character(packageVersion("monalisa")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_randomized_lasso_stability_selection.csv versions.yml
    """
}

workflow BIOC_MONALISA_RANDOMIZED_LASSO_STABILITY_SELECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ atac_peaks.bed, accessibility_changes.tsv, motifs.jaspar ] ]

    main:
    BIOC_MONALISA_RANDOMIZED_LASSO_STABILITY_SELECTION(ch_input)

    emit:
    tables   = BIOC_MONALISA_RANDOMIZED_LASSO_STABILITY_SELECTION.out.tables
    plots    = BIOC_MONALISA_RANDOMIZED_LASSO_STABILITY_SELECTION.out.plots
    objects  = BIOC_MONALISA_RANDOMIZED_LASSO_STABILITY_SELECTION.out.objects
    versions = BIOC_MONALISA_RANDOMIZED_LASSO_STABILITY_SELECTION.out.versions
}
