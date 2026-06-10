#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: HTqPCR — standard_qpcr_analysis
// Import, quality control, normalize, visualize, and analyze standard qPCR Ct data.
// Input: files.txt, sample1.txt
// Container: quay.io/biocontainers/bioconductor-htqpcr:1.64.0--r45hdfd78af_0
// R packages: HTqPCR
// Bioconductor: 3.20 | R: 4.4
// Requires: HTqPCR
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read sample info and raw Ct data
//  * 2. [Visualization & Output] Perform quality control and spatial layout visualization
//  * 3. [Core Analysis] Assess replicate concordance and variation
//  * 4. [Core Analysis] Filter and categorize Ct values
//  * 5. [Core Analysis] Normalize Ct data
//  * 6. [Visualization & Output] Visualize normalized data distributions, correlations, and clustering

nextflow.enable.dsl = 2

process BIOC_HTQPCR_STANDARD_QPCR_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    .bm_deps <- c("HTqPCR")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
                    
        library(HTqPCR)
        
        set.seed(123)
        
        path <- "."
        
        files <- read.delim(file.path(path, "files.txt"), stringsAsFactors = FALSE)
        conditions <- files[[2]]
        
        raw <- readCtData(files = files\$File, path = path)
        
        featureType(raw) <- rep(c("Target", "Endogenous Control"), length.out = nrow(raw))
        featurePos(raw) <- paste0(rep(LETTERS[1:16], each = ceiling(nrow(raw)/16)), rep(1:ceiling(nrow(raw)/16), 16))[1:nrow(raw)]
        featureClass(raw) <- factor(c("Marker", "TF", "Kinase")[sample(c(1, 1, 2, 2, 1, 3), nrow(raw), replace = TRUE)])
        
        qPCRraw <- raw
        
        pdf("HTqPCR_analysis_plots.pdf", width = 10, height = 8)
        
        g <- featureNames(raw)[1:min(10, nrow(raw))]
        plotCtOverview(raw, genes = g, xlim = c(0, 50), groups = conditions, conf.int = TRUE, ylim = c(0, 55))
        
        calib <- if ("Control" %in% conditions) "Control" else conditions[1]
        plotCtOverview(raw, genes = g, xlim = c(0, 50), groups = conditions, calibrator = calib)
        
        plotCtCard(raw, col.range = c(10, 35), well.size = 2.6)
        plotCtCard(raw, plot = "class", well.size = 2.6)
        
        plotCtReps(qPCRraw, card = min(2, ncol(qPCRraw)), percent = 20)
        
        raw.mix <- raw
        plotCtVariation(raw.mix, variation = "sd", log = TRUE, main = "SD of replicated features", col = "lightgrey")
        raw.variation <- plotCtVariation(raw.mix, type = "detail", add.featurenames = TRUE, pch = " ", cex = 1.2)
        
        raw.cat <- raw
        raw.cat <- setCategory(raw.cat)
        raw.cat <- filterCtData(raw.cat)
        raw.cat <- filterCategory(raw.cat)
        plotCtCategory(raw.cat)
        plotCtCategory(raw.cat, stratify = "class")
        plotCtCategory(raw.cat, by.feature = TRUE, cexRow = 0.1)
        
        q.norm <- normalizeCtData(raw.cat, norm = "quantile")
        sr.norm <- normalizeCtData(raw.cat, norm = "scale.rank")
        nr.norm <- normalizeCtData(raw.cat, norm = "norm.rank")
        
        d_genes <- featureNames(raw.cat)[1:min(2, nrow(raw.cat))]
        d.norm <- normalizeCtData(raw.cat, norm = "deltaCt", deltaCt.genes = d_genes)
        
        g.norm <- normalizeCtData(raw.cat, norm = "geometric.mean")
        
        plotCtCor(raw, main = "Ct correlation")
        plotCtDensity(sr.norm)
        plotCtHistogram(sr.norm)
        plotCtBoxes(sr.norm, stratify = "class")
        
        plotCtScatter(sr.norm, cards = c(1, min(2, ncol(sr.norm))), col = "type", diag = TRUE)
        plotCtPairs(sr.norm, col = "type", diag = TRUE)
        plotCtHeatmap(raw, gene.names = "", dist = "euclidean")
        plotCVBoxes(qPCRraw, stratify = "class")
        
        clusterCt(sr.norm, type = "samples")
        cluster.list <- clusterCt(sr.norm, type = "genes", n.cluster = min(6, nrow(sr.norm)), cex = 0.5)
        plotCtPCA(qPCRraw)
        getCtHistory(sr.norm)
        
        dev.off()
        
        write.csv(exprs(q.norm), "normalized_quantile_Ct.csv")
        write.csv(exprs(sr.norm), "normalized_scale_rank_Ct.csv")
        write.csv(exprs(nr.norm), "normalized_norm_rank_Ct.csv")
        write.csv(exprs(d.norm), "normalized_deltaCt_Ct.csv")
        write.csv(exprs(g.norm), "normalized_geometric_mean_Ct.csv")
        saveRDS(sr.norm, "normalized_scale_rank_object.rds")
        saveRDS(cluster.list, "gene_clusters.rds")
        write.table(getCtHistory(sr.norm), "processing_history.txt", sep = "\t", row.names = FALSE, quote = FALSE)

    writeLines(c(
        '"BIOC_HTQPCR_STANDARD_QPCR_ANALYSIS":',
        paste0('    HTqPCR: ', as.character(packageVersion('HTqPCR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standard_qpcr_analysis.csv versions.yml
    """
}

workflow BIOC_HTQPCR_STANDARD_QPCR_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ files.txt, sample1.txt ] ]

    main:
    BIOC_HTQPCR_STANDARD_QPCR_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_HTQPCR_STANDARD_QPCR_ANALYSIS.out.tables
    plots    = BIOC_HTQPCR_STANDARD_QPCR_ANALYSIS.out.plots
    objects  = BIOC_HTQPCR_STANDARD_QPCR_ANALYSIS.out.objects
    versions = BIOC_HTQPCR_STANDARD_QPCR_ANALYSIS.out.versions
}
