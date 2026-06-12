#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: epigenomix — rnaseq_chipseq_integration
// Integrate RNA-seq gene expression data with histone ChIP-seq data to classify genes based on concordant or discordant changes.
// Input: fpkm, mappedReads
// Container: quay.io/biocontainers/bioconductor-epigenomix:1.46.0--r44hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, GenomicRanges, epigenomix
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Construct an ExpressionSet from RNA-seq FPKM data
//  * 2. [Input & Preparation] Define promoter regions around TSS coordinates using GRanges and resize
//  * 3. [Visualization & Output] Summarize ChIP-seq reads in promoter regions using summarizeReads
//  * 4. [Core Analysis] Normalize ChIP-seq data using normalize
//  * 5. [Core Analysis] Integrate expression and ChIP-seq data using integrateData
//  * 6. [Core Analysis] Fit mixture models using mlMixModel or bayesMixModel

nextflow.enable.dsl = 2

process BIOC_EPIGENOMIX_RNASEQ_CHIPSEQ_INTEGRATION {
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
        
        # ----------------------------------------------------------------------
        # Stage 1: Load User Input Files
        # ----------------------------------------------------------------------
        
        # Load fpkm (Data frame containing RNA-seq FPKM values and TSS coordinates)
        if (file.exists("fpkm")) {
          fpkm <- tryCatch({
            readRDS("fpkm")
          }, error = function(e) {
            tryCatch({
              read.csv("fpkm", header = TRUE, stringsAsFactors = FALSE)
            }, error = function(e2) {
              read.table("fpkm", header = TRUE, stringsAsFactors = FALSE)
            })
          })
        } else {
          stop("Required input file 'fpkm' not found in the working directory.")
        }
        
        # Load mappedReads (GRangesList containing ChIP-seq reads)
        if (file.exists("mappedReads")) {
          mappedReads <- readRDS("mappedReads")
        } else {
          stop("Required input file 'mappedReads' not found in the working directory.")
        }
        
        # ----------------------------------------------------------------------
        # Stage 2: Construct an ExpressionSet from RNA-seq FPKM data
        # ----------------------------------------------------------------------
        # Dynamically identify sample columns by excluding known metadata columns
        metadata_cols <- c("tracking_id", "gene_id", "gene_short_name", "locus", 
                           "tss_id", "ensemble.estid", "chr", "start", "end", "strand", "tss")
        sample_cols <- setdiff(colnames(fpkm), metadata_cols)
        
        mat <- log2(as.matrix(fpkm[, sample_cols, drop = FALSE]))
        rownames(mat) <- fpkm\$tss_id
        eSet.seq <- ExpressionSet(mat)
        
        # Dynamically assign factors (handles replicates by removing trailing _[number])
        rna_groups <- as.factor(gsub("_[0-9]+\$", "", sample_cols))
        pData(eSet.seq)\$Condition <- rna_groups
        fData(eSet.seq)\$chr <- fpkm\$chr
        fData(eSet.seq)\$tss <- fpkm\$tss
        
        # ----------------------------------------------------------------------
        # Stage 3: Define promoter regions around TSS coordinates
        # ----------------------------------------------------------------------
        promoters.seq <- GRanges(
          seqnames = fData(eSet.seq)\$chr,
          ranges = IRanges(start = fData(eSet.seq)\$tss, width = 1),
          probe = featureNames(eSet.seq)
        )
        promoters.seq <- resize(promoters.seq, width = 3000, fix = "center")
        promoters.seq <- split(promoters.seq, elementMetadata(promoters.seq)\$probe)
        
        # ----------------------------------------------------------------------
        # Stage 4: Summarize ChIP-seq reads in promoter regions
        # ----------------------------------------------------------------------
        chipSetRaw.seq <- summarizeReads(mappedReads, promoters.seq, summarize = "add")
        
        # ----------------------------------------------------------------------
        # Stage 5: Normalize ChIP-seq data
        # ----------------------------------------------------------------------
        chipSet.seq <- normalize(chipSetRaw.seq, method = "quantile")
        
        # Dynamically assign factors for ChIP-seq data to match RNA-seq groups
        chip_groups <- as.factor(gsub("_[0-9]+\$", "", names(mappedReads)))
        chipSet.seq\$Condition <- chip_groups
        
        # ----------------------------------------------------------------------
        # Stage 6: Integrate expression and ChIP-seq data
        # ----------------------------------------------------------------------
        intData.seq <- integrateData(eSet.seq, chipSet.seq, factor = "Condition", reference = levels(rna_groups)[1])
        
        # ----------------------------------------------------------------------
        # Stage 7: Fit mixture models using mlMixModel
        # ----------------------------------------------------------------------
        mlmm <- mlMixModel(
          intData.seq[, "z"],
          normNull = c(2, 3),
          expNeg = 1,
          expPos = 4,
          sdNormNullInit = c(0.5, 1),
          rateExpNegInit = 0.5,
          rateExpPosInit = 0.5,
          pi = rep(1/4, 4)
        )
        
        # Extract classifications
        class_mlmm <- classification(mlmm, method = "maxDens")
        
        # ----------------------------------------------------------------------
        # Stage 8: Write Outputs
        # ----------------------------------------------------------------------
        
        # Save integrated data with classification results
        output_df <- data.frame(
          as.data.frame(intData.seq),
          classification = class_mlmm,
          stringsAsFactors = FALSE
        )
        write.csv(output_df, "integrated_data_classified.csv", row.names = TRUE)
        
        # Save the fitted model object
        saveRDS(mlmm, "mlmm_model.rds")
        
        # Generate and save diagnostic plots
        pdf("mixture_model_plots.pdf", width = 10, height = 5)
        par(mfrow = c(1, 2))
        plotComponents(mlmm, xlim = c(-2, 2), ylim = c(0, 3))
        plotClassification(mlmm)
        dev.off()
        
        cat("Pipeline completed successfully. Outputs saved to 'integrated_data_classified.csv', 'mlmm_model.rds', and 'mixture_model_plots.pdf'.\n")

    writeLines(c(
        '"BIOC_EPIGENOMIX_RNASEQ_CHIPSEQ_INTEGRATION":',
        paste0('    epigenomix: ', as.character(packageVersion('epigenomix')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rnaseq_chipseq_integration.csv versions.yml
    """
}

workflow BIOC_EPIGENOMIX_RNASEQ_CHIPSEQ_INTEGRATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ fpkm, mappedReads ] ]

    main:
    BIOC_EPIGENOMIX_RNASEQ_CHIPSEQ_INTEGRATION(ch_input)

    emit:
    tables   = BIOC_EPIGENOMIX_RNASEQ_CHIPSEQ_INTEGRATION.out.tables
    plots    = BIOC_EPIGENOMIX_RNASEQ_CHIPSEQ_INTEGRATION.out.plots
    objects  = BIOC_EPIGENOMIX_RNASEQ_CHIPSEQ_INTEGRATION.out.objects
    versions = BIOC_EPIGENOMIX_RNASEQ_CHIPSEQ_INTEGRATION.out.versions
}
