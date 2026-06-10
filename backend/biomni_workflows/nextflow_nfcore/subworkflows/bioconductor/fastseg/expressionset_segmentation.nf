#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: fastseg — expressionset_segmentation
// Segment microarray expression data represented as an ExpressionSet object.
// Input: eSet
// Container: quay.io/biocontainers/bioconductor-fastseg:1.56.0--r45ha27e39d_0
// R packages: Biobase, GenomicRanges, fastseg
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, GenomicRanges, fastseg
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load Biobase and fastseg packages
//  * 2. [Input & Preparation] Construct or load the ExpressionSet object
//  * 3. [Core Analysis] Run segmentation using fastseg

nextflow.enable.dsl = 2

process BIOC_FASTSEG_EXPRESSIONSET_SEGMENTATION {
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
    .bm_deps <- c("Biobase", "GenomicRanges", "fastseg")
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
            
            # 1. Load required libraries
            library(fastseg)
            library("Biobase")
            library(GenomicRanges)
            
            # 2. Read the input ExpressionSet object from the working directory
            input_file <- "eSet"
            if (!file.exists(input_file)) {
              if (file.exists("eSet.rds")) {
                input_file <- "eSet.rds"
              } else if (file.exists("eSet.RData")) {
                input_file <- "eSet.RData"
              } else {
                stop("Error: Input file 'eSet', 'eSet.rds', or 'eSet.RData' not found in the working directory.")
              }
            }
            
            if (grepl("\\\\.RData\$", input_file, ignore.case = TRUE)) {
              env <- new.env()
              load(input_file, envir = env)
              objs <- ls(env)
              eset_name <- objs[sapply(objs, function(x) inherits(env[[x]], "ExpressionSet"))][1]
              if (is.na(eset_name)) {
                stop("No ExpressionSet object found in the loaded RData file.")
              }
              input_eSet <- env[[eset_name]]
            } else {
              input_eSet <- readRDS(input_file)
            }
            
            # Extract components from the input ExpressionSet to feed into the documented workflow
            if ("intensity" %in% assayDataElementNames(input_eSet)) {
              data <- assayDataElement(input_eSet, "intensity")
            } else {
              data <- exprs(input_eSet)
            }
            
            fd <- pData(featureData(input_eSet))
            if ("chrom" %in% colnames(fd)) {
              chrom <- fd\$chrom
              # Strip "chr" prefix if present, as the documented code prepends it
              chrom <- gsub("^chr", "", chrom)
            } else if ("Chromosome" %in% colnames(fd)) {
              chrom <- fd\$Chromosome
            } else {
              stop("Chromosome annotation not found in featureData. Expected column 'chrom' or 'Chromosome'.")
            }
            
            if ("start" %in% colnames(fd)) {
              maploc <- fd\$start
            } else if ("Position" %in% colnames(fd)) {
              maploc <- fd\$Position
            } else {
              stop("Position annotation not found in featureData. Expected column 'start' or 'Position'.")
            }
            
            samplenames <- sampleNames(input_eSet)
            
            # 3. Run the EXACT documented workflow
            # Format the featureData of the existing ExpressionSet directly
            fData(input_eSet)\$chrom <- paste("chr", chrom, sep="")
            fData(input_eSet)\$start <- maploc
            fData(input_eSet)\$end   <- maploc
            
            res <- fastseg(input_eSet)
            head(res)
            
            # 4. Save meaningful outputs
            # Save the GRanges result object
            saveRDS(res, "segmentation_results.rds")
            
            # Save the results as a CSV table
            write.csv(as.data.frame(res), "segmentation_results.csv", row.names=FALSE)
            
            # Generate diagnostic whole-genome segmentation plot
            pdf("segmentation_plot.pdf", width=12, height=8)
            tryCatch({
              gr <- GRanges(seqnames=paste("chr",chrom,sep=""), ranges=IRanges(maploc, end=maploc))
              mcols(gr) <- data
              colnames(mcols(gr)) <- samplenames
              segPlot(gr, res, plot.type="w")
            }, error = function(e) {
              message("Plotting skipped or failed: ", e\$message)
            })
            dev.off()

    writeLines(c(
        '"BIOC_FASTSEG_EXPRESSIONSET_SEGMENTATION":',
        paste0('    fastseg: ', as.character(packageVersion('fastseg')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_expressionset_segmentation.csv versions.yml
    """
}

workflow BIOC_FASTSEG_EXPRESSIONSET_SEGMENTATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ eSet ] ]

    main:
    BIOC_FASTSEG_EXPRESSIONSET_SEGMENTATION(ch_input)

    emit:
    tables   = BIOC_FASTSEG_EXPRESSIONSET_SEGMENTATION.out.tables
    plots    = BIOC_FASTSEG_EXPRESSIONSET_SEGMENTATION.out.plots
    objects  = BIOC_FASTSEG_EXPRESSIONSET_SEGMENTATION.out.objects
    versions = BIOC_FASTSEG_EXPRESSIONSET_SEGMENTATION.out.versions
}
