#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: gCrisprTools — single_pooled_screen
// Preprocess, normalize, analyze, and visualize a single pooled CRISPR/shRNA screen to identify candidate target genes.
// Input: es, ann, sk, aln, essential.genes, genesetdb
// Container: quay.io/biocontainers/bioconductor-gcrisprtools:2.16.0--r45hdfd78af_0
// R packages: Biobase, gCrisprTools, limma, sparrow
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, gCrisprTools, limma, sparrow
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Filter low-abundance reads using ct.filterReads
//  * 2. [Input & Preparation] Prepare annotation using ct.prepareAnnotation
//  * 3. [Core Analysis] Normalize guide counts using ct.normalizeGuides
//  * 4. [Core Analysis] Perform differential expression analysis using voom, lmFit, contrasts.fit, and eBayes from limma
//  * 5. [Visualization & Output] Summarize gRNA signals to target level using ct.generateResults
//  * 6. [Visualization & Output] Perform quality control visualizations (ct.alignmentChart, ct.rawCountDensities, ct.gRNARankByReplicate, ct.viewControls, ct.guide
//  * 7. [Visualization & Output] Visualize target-level results (ct.contrastBarchart, ct.topTargets, ct.stackGuides, ct.viewGuides, ct.signalSummary)
//  * 8. [Core Analysis] Perform gene set enrichment analysis (ct.targetSetEnrichment, ct.ROC, ct.PRC, ct.seas)
//  * 9. [Visualization & Output] Generate HTML reports (ct.makeReport, ct.makeQCReport, ct.makeContrastReport)

nextflow.enable.dsl = 2

process BIOC_GCRISPRTOOLS_SINGLE_POOLED_SCREEN {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("Biobase", "gCrisprTools", "limma", "sparrow")
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
        
        # Load required libraries
        library(Biobase)
        library(limma)
        library(gCrisprTools)
        library(sparrow)
        
        # ==========================================
        # 1. Load User Input Files
        # ==========================================
        # The pipeline reads exactly these files from the working directory:
        es              <- readRDS("es.rds")
        ann             <- readRDS("ann.rds")
        sk              <- readRDS("sk.rds")
        aln             <- readRDS("aln.rds")
        essential.genes <- readRDS("essential.genes.rds")
        genesetdb       <- readRDS("genesetdb.rds")
        
        # ==========================================
        # 2. Setup Design and Contrasts
        # ==========================================
        # Construct design matrix using the sample key factor 'sk'
        design <- model.matrix(~ 0 + sk)
        colnames(design) <- levels(sk)
        
        # Define contrasts. We attempt to use the standard contrast from the vignette.
        # If the expected levels are not present, we dynamically construct a contrast.
        if (all(c("DeathExpansion", "ControlExpansion") %in% colnames(design))) {
          contrasts <- makeContrasts(DeathExpansion - ControlExpansion, levels = design)
        } else {
          lvl <- colnames(design)
          comp <- paste0(lvl[length(lvl)], " - ", lvl[max(1, length(lvl)-1)])
          contrasts <- makeContrasts(contrasts = comp, levels = design)
        }
        
        # ==========================================
        # 3. Preprocessing and Normalization
        # ==========================================
        # Filter low-abundance reads
        es <- ct.filterReads(es, trim = 1000, sampleKey = sk)
        
        # Open PDF device to capture all QC and results plots
        pdf("gCrisprTools_QC_and_Results_Plots.pdf", width = 8, height = 8)
        
        # Normalize guide counts
        es <- ct.normalizeGuides(es, method = "scale", plot.it = TRUE)
        
        # ==========================================
        # 4. Differential Expression Analysis (limma/voom)
        # ==========================================
        vm <- voom(exprs(es), design)
        fit <- lmFit(vm, design)
        fit <- contrasts.fit(fit, contrasts)
        fit <- eBayes(fit)
        
        # Identify the most likely control gene (usually the one with the most guides)
        control_gene <- names(sort(table(ann\$geneSymbol), decreasing = TRUE))[1]
        
        # Prepare annotation mapping
        ann <- ct.prepareAnnotation(ann, fit, controls = control_gene)
        
        # ==========================================
        # 5. Summarize gRNA Signals to Target Level
        # ==========================================
        resultsDF <- ct.generateResults(
          fit, 
          annotation = ann, 
          RRAalphaCutoff = 0.1, 
          permutations = 1000, 
          scoring = "combined", 
          permutation.seed = 2
        )
        
        # Create alternative annotations for multi-targeting reagents
        altann <- sapply(ann\$ID, function(x) {
          out <- as.character(ann\$geneSymbol)[ann\$ID %in% x]
          if (runif(1) < 0.01) {
            out <- c(out, sample(as.character(ann\$geneSymbol), size = 1))
          }
          return(out)
        }, simplify = FALSE)
        
        # Generate results with alternative annotations
        altResultsDF <- ct.generateResults(
          fit, 
          annotation = ann, 
          RRAalphaCutoff = 0.1, 
          permutations = 1000, 
          scoring = "combined", 
          alt.annotation = altann, 
          permutation.seed = 2
        )
        
        # Generate simplified target-level results
        targetResultDF <- ct.simpleResult(resultsDF)
        
        # ==========================================
        # 6. Quality Control Visualizations
        # ==========================================
        tryCatch({ ct.alignmentChart(aln, sk) }, error = function(e) { warning("ct.alignmentChart failed: ", e\$message) })
        tryCatch({ ct.rawCountDensities(es, sk) }, error = function(e) { warning("ct.rawCountDensities failed: ", e\$message) })
        tryCatch({ ct.gRNARankByReplicate(es, sk) }, error = function(e) { warning("ct.gRNARankByReplicate failed: ", e\$message) })
        
        # Show locations of Non-Targeting Control (NTC) gRNAs
        tryCatch({ 
          ct.gRNARankByReplicate(es, sk, annotation = ann, geneSymb = control_gene) 
        }, error = function(e) { 
          warning("ct.gRNARankByReplicate for control failed: ", e\$message) 
        })
        
        # Visualize control guide behavior
        tryCatch({ ct.viewControls(es, ann, sk, normalize = FALSE) }, error = function(e) { warning("ct.viewControls (unnormalized) failed: ", e\$message) })
        tryCatch({ ct.viewControls(es, ann, sk, normalize = TRUE) }, error = function(e) { warning("ct.viewControls (normalized) failed: ", e\$message) })
        
        # Visualize GC bias
        tryCatch({ ct.GCbias(es, ann, sk) }, error = function(e) { warning("ct.GCbias (eset) failed: ", e\$message) })
        tryCatch({ ct.GCbias(fit, ann, sk) }, error = function(e) { warning("ct.GCbias (fit) failed: ", e\$message) })
        
        # View most variable gRNAs/Genes
        tryCatch({ ct.stackGuides(es, sk, plotType = "gRNA", annotation = ann, nguides = 40) }, error = function(e) { warning("ct.stackGuides (gRNA) failed: ", e\$message) })
        tryCatch({ ct.stackGuides(es, sk, plotType = "Target", annotation = ann) }, error = function(e) { warning("ct.stackGuides (Target) failed: ", e\$message) })
        
        # Stack guides subsetted by a specific sample group
        tryCatch({ 
          subset_samples <- colnames(es)[sk == levels(sk)[length(levels(sk))]]
          ct.stackGuides(es, sk, plotType = "Target", annotation = ann, subset = subset_samples) 
        }, error = function(e) { 
          warning("ct.stackGuides (Target subset) failed: ", e\$message) 
        })
        
        # View CDF of genes/guides
        tryCatch({ ct.guideCDF(es, sk, plotType = "gRNA") }, error = function(e) { warning("ct.guideCDF (gRNA) failed: ", e\$message) })
        tryCatch({ ct.guideCDF(es, sk, plotType = "Target", annotation = ann) }, error = function(e) { warning("ct.guideCDF (Target) failed: ", e\$message) })
        
        # ==========================================
        # 7. Target-Level Visualization and Analysis
        # ==========================================
        tryCatch({ ct.contrastBarchart(resultsDF) }, error = function(e) { warning("ct.contrastBarchart failed: ", e\$message) })
        
        # View top enriched/depleted candidates
        tryCatch({ ct.topTargets(fit, resultsDF, ann, targets = 10, enrich = TRUE) }, error = function(e) { warning("ct.topTargets (enrich) failed: ", e\$message) })
        tryCatch({ ct.topTargets(fit, resultsDF, ann, targets = 10, enrich = FALSE) }, error = function(e) { warning("ct.topTargets (deplete) failed: ", e\$message) })
        
        # View behavior of reagents targeting a specific gene of interest
        target_of_interest <- if (nrow(resultsDF) > 0) as.character(resultsDF\$geneSymbol[1]) else as.character(ann\$geneSymbol[1])
        tryCatch({ ct.viewGuides(target_of_interest, fit, ann) }, error = function(e) { warning("ct.viewGuides for target failed: ", e\$message) })
        tryCatch({ ct.gRNARankByReplicate(es, sk, annotation = ann, geneSymb = target_of_interest) }, error = function(e) { warning("ct.gRNARankByReplicate for target failed: ", e\$message) })
        
        # Observe effects detected for sets of targets
        # Safely sample unique gene symbols to avoid sampling errors if there are too few genes
        unique_genes <- unique(resultsDF\$geneSymbol)
        target_set_a <- if (length(unique_genes) >= 3) sample(unique_genes, 3) else unique_genes
        target_set_b <- if (length(unique_genes) >= 2) sample(unique_genes, 2) else unique_genes
        
        tryCatch({
          ct.signalSummary(resultsDF, targets = list('TargetSetA' = target_set_a, 'TargetSetB' = target_set_b))
        }, error = function(e) {
          warning("ct.signalSummary failed: ", e\$message)
        })
        
        # ==========================================
        # 8. Gene Set Enrichment Analysis
        # ==========================================
        # Test known gene set for enrichment
        tryCatch({ ct.targetSetEnrichment(resultsDF, essential.genes) }, error = function(e) { warning("ct.targetSetEnrichment failed: ", e\$message) })
        
        # ROC and PRC analysis
        ROC <- tryCatch({ ct.ROC(resultsDF, essential.genes, direction = "deplete") }, error = function(e) { warning("ct.ROC failed: ", e\$message); NULL })
        PRC <- tryCatch({ ct.PRC(resultsDF, essential.genes, direction = "deplete") }, error = function(e) { warning("ct.PRC failed: ", e\$message); NULL })
        
        if (!is.null(ROC)) { tryCatch({ show(ROC) }, error = function(e) { warning("show(ROC) failed: ", e\$message) }) }
        
        # Ontological enrichment via sparrow
        tryCatch({ ct.seas(resultsDF, gdb = genesetdb) }, error = function(e) { warning("ct.seas failed: ", e\$message) })
        
        # Convert identifiers and run enrichment again
        genesetdb.GREAT <- tryCatch({
          sparrow::convertIdentifiers(genesetdb, from = 'geneID', to = 'geneSymbol', xref = ann)
        }, error = function(e) {
          warning("sparrow::convertIdentifiers failed: ", e\$message)
          NULL
        })
        
        if (!is.null(genesetdb.GREAT)) {
          tryCatch({ ct.seas(resultsDF, gdb = genesetdb.GREAT) }, error = function(e) { warning("ct.seas with genesetdb.GREAT failed: ", e\$message) })
        }
        
        # Close the PDF graphics device
        dev.off()
        
        # ==========================================
        # 9. Generate HTML Reports
        # ==========================================
        # Reports are wrapped in tryCatch to handle environments lacking pandoc/latex gracefully
        tryCatch({
          path2report <- ct.makeReport(fit = fit, eset = es, sampleKey = sk, annotation = ann, results = resultsDF, aln = aln, outdir = ".")
          message("Report generated at: ", path2report)
        }, error = function(e) {
          warning("ct.makeReport failed: ", e\$message)
        })
        
        tryCatch({
          path2QC <- ct.makeQCReport(es, trim = 1000, log2.ratio = 0.05, sampleKey = sk, annotation = ann, aln = aln, identifier = 'Crispr_QC_Report', lib.size = NULL )
          message("QC Report generated at: ", path2QC)
        }, error = function(e) {
          warning("ct.makeQCReport failed: ", e\$message)
        })
        
        tryCatch({
          path2Contrast <- ct.makeContrastReport(eset = es, fit = fit, sampleKey = sk, results = resultsDF, annotation = ann, comparison.id = NULL, identifier = 'Crispr_Contrast_Report')
          message("Contrast Report generated at: ", path2Contrast)
        }, error = function(e) {
          warning("ct.makeContrastReport failed: ", e\$message)
        })
        
        # ==========================================
        # 10. Save Output Objects
        # ==========================================
        write.csv(resultsDF, file = "resultsDF.csv", row.names = TRUE)
        write.csv(targetResultDF, file = "targetResultDF.csv", row.names = TRUE)
        saveRDS(resultsDF, file = "resultsDF.rds")
        saveRDS(targetResultDF, file = "targetResultDF.rds")
        if (!is.null(ROC)) { saveRDS(ROC, file = "ROC.rds") }
        if (!is.null(PRC)) { saveRDS(PRC, file = "PRC.rds") }
        
        message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_GCRISPRTOOLS_SINGLE_POOLED_SCREEN":',
        paste0('    gCrisprTools: ', as.character(packageVersion('gCrisprTools')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_pooled_screen.csv versions.yml
    """
}

workflow BIOC_GCRISPRTOOLS_SINGLE_POOLED_SCREEN_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ es, ann, sk, aln, essential.genes, genesetdb ] ]

    main:
    BIOC_GCRISPRTOOLS_SINGLE_POOLED_SCREEN(ch_input)

    emit:
    tables   = BIOC_GCRISPRTOOLS_SINGLE_POOLED_SCREEN.out.tables
    plots    = BIOC_GCRISPRTOOLS_SINGLE_POOLED_SCREEN.out.plots
    objects  = BIOC_GCRISPRTOOLS_SINGLE_POOLED_SCREEN.out.objects
    versions = BIOC_GCRISPRTOOLS_SINGLE_POOLED_SCREEN.out.versions
}
