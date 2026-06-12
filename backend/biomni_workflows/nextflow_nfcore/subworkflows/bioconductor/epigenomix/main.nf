#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: epigenomix — microarray_chipseq_integration
// Integrate microarray gene expression data with histone ChIP-seq data to classify genes based on concordant or discordant changes.
// Input: eSet, mappedReads, transToTSS
// Container: quay.io/biocontainers/bioconductor-epigenomix:1.46.0--r44hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, GenomicRanges, epigenomix
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Map probes to transcripts and obtain TSS coordinates
//  * 2. [Core Analysis] Calculate promoter regions for each probe using matchProbeToPromoter
//  * 3. [Visualization & Output] Summarize ChIP-seq reads in promoter regions using summarizeReads
//  * 4. [Core Analysis] Normalize ChIP-seq data using normalize
//  * 5. [Core Analysis] Integrate expression and ChIP-seq data using integrateData
//  * 6. [Core Analysis] Fit mixture models using mlMixModel or bayesMixModel
//  * 7. [Visualization & Output] Plot components and classification using plotComponents and plotClassification

nextflow.enable.dsl = 2

process BIOC_EPIGENOMIX_MICROARRAY_CHIPSEQ_INTEGRATION {
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
    .bm_deps <- c("epigenomix", "Biobase", "GenomicRanges")
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
        library(epigenomix)
        library(Biobase)
        library(GenomicRanges)
        
        # ==========================================
        # 1. Read User Input Files
        # ==========================================
        
        if (file.exists("eSet.rds")) {
            eSet <- readRDS("eSet.rds")
        } else {
            stop("Error: eSet.rds not found in the working directory.")
        }
        
        if (file.exists("mappedReads.rds")) {
            mappedReads <- readRDS("mappedReads.rds")
        } else {
            stop("Error: mappedReads.rds not found in the working directory.")
        }
        
        if (file.exists("transToTSS.rds")) {
            transToTSS <- readRDS("transToTSS.rds")
        } else if (file.exists("transToTSS.csv")) {
            transToTSS <- read.csv("transToTSS.csv", stringsAsFactors = FALSE)
        } else {
            stop("Error: transToTSS.rds or transToTSS.csv not found in the working directory.")
        }
        
        # ==========================================
        # 2. Map Probes to Transcripts and TSS
        # ==========================================
        
        if ("transcript" %in% colnames(fData(eSet))) {
            probeToTrans <- as.character(fData(eSet)\$transcript)
        } else {
            probeToTrans <- as.character(fData(eSet)[[1]])
        }
        probeToTrans <- strsplit(probeToTrans, ",")
        names(probeToTrans) <- featureNames(eSet)
        
        promoters <- matchProbeToPromoter(probeToTrans, transToTSS, promWidth=6000, mode="union")
        
        # ==========================================
        # 3. Summarize and Normalize ChIP-seq Reads
        # ==========================================
        
        chipSetRaw <- summarizeReads(mappedReads, promoters, summarize="add")
        chipSet <- normalize(chipSetRaw, method="quantile")
        
        # ==========================================
        # 4. Integrate Expression and ChIP-seq Data
        # ==========================================
        
        factor_name <- colnames(pData(eSet))[1]
        for (col in colnames(pData(eSet))) {
            if (length(levels(as.factor(pData(eSet)[[col]]))) == 2) {
                factor_name <- col
                break
            }
        }
        factor_levels <- as.factor(pData(eSet)[[factor_name]])
        ref_level <- levels(factor_levels)[1]
        
        if (all(colnames(chipSet) %in% rownames(pData(eSet)))) {
            chipSet[[factor_name]] <- pData(eSet)[colnames(chipSet), factor_name]
        } else if (ncol(chipSet) == ncol(eSet)) {
            chipSet[[factor_name]] <- factor_levels
        } else {
            lvls <- levels(factor_levels)
            chip_groups <- sapply(colnames(chipSet), function(x) {
                m <- lvls[sapply(lvls, function(l) grepl(l, x, ignore.case=TRUE))]
                if(length(m) == 1) m else NA
            })
            if(any(is.na(chip_groups))) {
                chip_groups[is.na(chip_groups)] <- rep(lvls, length.out = sum(is.na(chip_groups)))
            }
            chipSet[[factor_name]] <- factor(chip_groups, levels = lvls)
        }
        
        intData <- integrateData(eSet, chipSet, factor=factor_name, reference=ref_level)
        
        # ==========================================
        # 5. Fit Mixture Models
        # ==========================================
        
        # Maximum Likelihood Mixture Model
        mlmm = mlMixModel(intData[,"z"], normNull=c(2, 3), expNeg=1, expPos=4, 
                          sdNormNullInit=c(0.5, 1), rateExpNegInit=0.5, rateExpPosInit=0.5, 
                          pi=rep(1/4, 4))
        
        # Bayesian Mixture Model
        set.seed(1515)
        bayesmm = bayesMixModel(intData[,"z"], normNull=c(2, 3), expNeg=1, expPos=4, 
                                sdNormNullInit=c(0.5, 1), rateExpNegInit=0.5, rateExpPosInit=0.5, 
                                shapeNorm0=c(10, 10), scaleNorm0=c(10, 10), shapeExpNeg0=0.01, 
                                scaleExpNeg0=0.01, shapeExpPos0=0.01, scaleExpPos0=0.01, 
                                pi=rep(1/4, 4), sdAlpha=1, itb=2000, nmc=8000, thin=5)
        
        # ==========================================
        # 6. Visualization and Output Generation
        # ==========================================
        
        # Save Plots
        pdf("mixture_model_plots.pdf", width=10, height=10)
        par(mfrow=c(2,2))
        plotComponents(mlmm, xlim=c(-2, 2), ylim=c(0, 3))
        title(main="ML Model Components")
        plotClassification(mlmm)
        title(main="ML Model Classification")
        plotComponents(bayesmm, xlim=c(-2, 2), ylim=c(0, 3))
        title(main="Bayesian Model Components")
        plotClassification(bayesmm, method="mode")
        title(main="Bayesian Model Classification")
        dev.off()
        
        # Save Classification Comparison Table
        compTable <- table(classification(mlmm, method="maxDens"), classification(bayesmm, method="mode"))
        write.csv(as.data.frame(compTable), "classification_comparison.csv", row.names=TRUE)
        
        # Extract and Save Positive Probes (Component 4)
        posProbes <- rownames(intData)[classification(bayesmm, method="mode") == 4]
        write.table(posProbes, "positive_probes.txt", row.names=FALSE, col.names=FALSE, quote=FALSE)
        
        # Save Integrated Data with Classifications
        integratedResults <- as.data.frame(intData)
        integratedResults\$mlmm_class <- classification(mlmm, method="maxDens")
        integratedResults\$bayes_class <- classification(bayesmm, method="mode")
        write.csv(integratedResults, "integrated_data_classification.csv", row.names=TRUE)
        
        # Save Model Objects
        saveRDS(mlmm, "mlmm_model.rds")
        saveRDS(bayesmm, "bayesmm_model.rds")

    writeLines(c(
        '"BIOC_EPIGENOMIX_MICROARRAY_CHIPSEQ_INTEGRATION":',
        paste0('    epigenomix: ', as.character(packageVersion('epigenomix')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_microarray_chipseq_integration.csv versions.yml
    """
}

workflow BIOC_EPIGENOMIX_MICROARRAY_CHIPSEQ_INTEGRATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ eSet, mappedReads, transToTSS ] ]

    main:
    BIOC_EPIGENOMIX_MICROARRAY_CHIPSEQ_INTEGRATION(ch_input)

    emit:
    tables   = BIOC_EPIGENOMIX_MICROARRAY_CHIPSEQ_INTEGRATION.out.tables
    plots    = BIOC_EPIGENOMIX_MICROARRAY_CHIPSEQ_INTEGRATION.out.plots
    objects  = BIOC_EPIGENOMIX_MICROARRAY_CHIPSEQ_INTEGRATION.out.objects
    versions = BIOC_EPIGENOMIX_MICROARRAY_CHIPSEQ_INTEGRATION.out.versions
}
