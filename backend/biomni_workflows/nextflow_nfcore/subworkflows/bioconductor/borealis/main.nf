#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: borealis — outlier_methylation_detection
// Run the Borealis pipeline on Bismark alignment files to detect outlier methylated CpG sites, perform post-processing, and visualize specific outlier sites.
// Input: extdata
// Container: quay.io/biocontainers/bioconductor-borealis:1.14.0--r45hdfd78af_0
// R packages: GenomicRanges, annotatr, borealis
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, annotatr, borealis
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Run the core Borealis pipeline using runBorealis to generate DML files and CpG models. 2. Read the resulting DML TSV files into R 

nextflow.enable.dsl = 2

process BIOC_BOREALIS_OUTLIER_METHYLATION_DETECTION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20-slim"

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
    .bm_deps <- c("GenomicRanges", "annotatr", "borealis")
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
            library(borealis)
            library(GenomicRanges)
            
            # Define input and output directories
            extdata <- "extdata"
            outdir <- "borealis_output"
            
            # Define genome version (Update this to match the genome of your Bismark alignment data)
            genome.version <- "hg19" 
            
            if (!dir.exists(outdir)) {
                dir.create(outdir, recursive = TRUE)
            }
            
            # Verify input directory exists
            if (!dir.exists(extdata)) {
                stop("Input directory 'extdata' does not exist in the working directory.")
            }
            
            outprefix_str <- "borealis_"
            model_prefix_str <- "CpG_model"
        
            # Run borealis
            results <- runBorealis(extdata, nThreads=2, suffix=".gz",
                                    outprefix=file.path(outdir, outprefix_str), 
                                    modelOutPrefix=file.path(outdir, model_prefix_str))
            
            # Read in the name of all files for analysis
            borealis_in <- dir(outdir, pattern=".*DMLs\\\\.tsv")
            
            # Read in list of Borealis output files and create a dataframe for each
            listGRanges <- list()
            list_object_names <- character()
        
            for (file in borealis_in) {
                name <- sub("_DMLs\\\\.tsv", "", file)
                list_object_names <- c(list_object_names, name)
                listGRanges[[name]] <- GenomicRanges::makeGRangesFromDataFrame(
                            read.table(file.path(outdir, file), header=TRUE,
                            stringsAsFactors=FALSE), start.field="pos", end.field="pos.1", 
                            seqnames.field="chr", keep.extra.columns=TRUE)
            }
            
            # Add sample ID and a corrected p-value to each and output as new files (.padj)
            for (i in seq_along(listGRanges)) {
                sample <- sub(paste0("^", outprefix_str), "", list_object_names[i])
                sample <- sub("_chr.*", "", sample)
                listGRanges[[i]]\$sampleID <- sample
                listGRanges[[i]]\$pAdj <- p.adjust(listGRanges[[i]]\$pVal, method="BH")
            }
            
            # Create a single GRanges obect with data for all samples and a dataframe for summaries
            combined_files <- Reduce(c, listGRanges)
            combined_files_df <- data.frame(combined_files)
            
            # Save main outputs
            write.csv(combined_files_df, file=file.path(outdir, "combined_borealis_results.csv"), row.names=FALSE)
            saveRDS(combined_files, file=file.path(outdir, "combined_borealis_results.rds"))
            
            # Find the most significant CpG site and corresponding sample dynamically
            min_p_row <- combined_files_df[which.min(combined_files_df\$pVal), ]
            top_site <- paste0(min_p_row\$seqnames, ":", min_p_row\$start)
            top_sample <- min_p_row\$sampleID
            top_chr <- as.character(min_p_row\$seqnames)
        
            # Use Borealis plotting function to investigate this site further
            pdf(file.path(outdir, "outlier_CpG_site_plot.pdf"))
            tryCatch({
                p <- plotCpGsite(top_site, sampleOfInterest=top_sample,
                            modelFile=file.path(outdir, paste0(model_prefix_str, "_", top_chr, ".csv")),
                            methCountFile=file.path(outdir, paste0(model_prefix_str, "_rawMethCount_", top_chr, ".tsv")),
                            totalCountFile=file.path(outdir, paste0(model_prefix_str, "_rawTotalCount_", top_chr, ".tsv")))
                lapply(p, print)
            }, error = function(e) {
                warning("Plotting failed: ", e\$message)
            })
            dev.off()
            
            # Optional annotation and summarization step using annotatr
            tryCatch({
                library(annotatr)
                
                # Select annotation classes we want from annotatr
                myAnnots <- c('_genes_promoters', '_genes_5UTRs', '_genes_exons', '_genes_3UTRs','_cpg_islands')
            
                # Read in top sample Grange data for annotation
                dmrs.gr <- subset(combined_files, sampleID == top_sample)
            
                # Annotate using annotatr
                myAnnots <- paste(genome.version, myAnnots, sep="")
                annots.all.gr <- annotatr::build_annotations(genome = genome.version, annotations = myAnnots)
                allAnnot <- annotatr::annotate_regions(regions=dmrs.gr, annotations=annots.all.gr, ignore.strand=TRUE, minoverlap=0)
            
                padjThresh <- 0.05
            
                # Calculate how may CpGs per annotatr feature and store in dataframe
                allAnnot <- as.data.frame(allAnnot)
                featureids <- allAnnot\$annot.id
                featurecnts <- as.data.frame(table(featureids))
                colnames(featurecnts) <- c("annot.id", "NoSites")
            
                # Calculate how many sites per feature pass p-value threshold
                signifonly <- subset(allAnnot, pAdj<=padjThresh)
                signifonly <- signifonly\$annot.id
                signifonlycnt <- as.data.frame(table(signifonly))
                colnames(signifonlycnt) <- c("annot.id", "signifCount")
                featurecnts <- merge(featurecnts, signifonlycnt, by.x="annot.id", by.y="annot.id", all.x=TRUE)
            
                # What fraction of sites per feature pass p-value threshold?
                featurecnts\$fractionSignif <- featurecnts\$signifCount/featurecnts\$NoSites
            
                # Combine the data for final output
                locations <- subset(allAnnot, select=c("annot.id", "annot.seqnames", "annot.start", "annot.end"))
                featurecnts <- merge(unique(locations), featurecnts, by="annot.id")
                genemap <- unique(cbind(allAnnot\$annot.symbol, allAnnot\$annot.id, allAnnot\$annot.tx_id,allAnnot\$annot.width, allAnnot\$sampleID))
                colnames(genemap) <- c("annot.symbol", "annot.id", "annot.tx_id", "annot.width", "SampleID")
            
                summarized <- merge(featurecnts, genemap, by="annot.id")
                summarized\$signifCount[is.na(summarized\$signifCount)] <- 0
                summarized\$fractionSignif[is.na(summarized\$fractionSignif)] <- 0
            
                # Save summarized features
                write.csv(summarized, file=file.path(outdir, "summarized_epigenetic_features.csv"), row.names=FALSE)
            }, error = function(e) {
                warning("Annotation and summarization step skipped or failed: ", e\$message)
            })

    writeLines(c(
        '"BIOC_BOREALIS_OUTLIER_METHYLATION_DETECTION":',
        paste0('    borealis: ', as.character(packageVersion('borealis')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_outlier_methylation_detection.csv versions.yml
    """
}

workflow BIOC_BOREALIS_OUTLIER_METHYLATION_DETECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ extdata ] ]

    main:
    BIOC_BOREALIS_OUTLIER_METHYLATION_DETECTION(ch_input)

    emit:
    tables   = BIOC_BOREALIS_OUTLIER_METHYLATION_DETECTION.out.tables
    plots    = BIOC_BOREALIS_OUTLIER_METHYLATION_DETECTION.out.plots
    objects  = BIOC_BOREALIS_OUTLIER_METHYLATION_DETECTION.out.objects
    versions = BIOC_BOREALIS_OUTLIER_METHYLATION_DETECTION.out.versions
}
