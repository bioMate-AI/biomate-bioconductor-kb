#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: PREDA — sodegir_combined_analysis
// Integrate gene expression and copy number data to identify genomic regions with significant overlapping alterations (amplified/deleted regions) across multiple 
// Input: sampleinfoGE_PREDA.txt, Raw Affymetrix .CEL files, CNAG_data_PREDA.txt, SNPAnnot100k.csv
// Container: quay.io/biocontainers/bioconductor-preda:1.56.0--r45hdfd78af_0
// R packages: PREDA, affy
// Bioconductor: 3.20 | R: 4.4
// Requires: PREDA, affy
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Preprocess gene expression data for SODEGIR using SODEGIRpreprocessingGE. 2. Run PREDA analysis on gene expression data using PRED

nextflow.enable.dsl = 2

process BIOC_PREDA_SODEGIR_COMBINED_ANALYSIS {
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
    .bm_deps <- c("PREDA", "affy")
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
    library(PREDA)
    library(affy)
    
    # ==========================================
    # STEP 0: Read User Input Files
    # ==========================================
    
    # Read sample metadata for gene expression
    sampleinfo <- read.table("sampleinfoGE_PREDA.txt", sep="\t", header=TRUE, stringsAsFactors=FALSE)
    
    # Read raw Affymetrix .CEL files based on the metadata
    AffybatchRCC <- ReadAffy(filenames = sampleinfo\$Arrayname)
    
    # Set custom CDF name and annotation
    AffybatchRCC@cdfName <- "hgu133plus2"
    annotation(AffybatchRCC) <- "hgu133plus2"
    
    # Assign phenoData to the AffyBatch object
    rownames(sampleinfo) <- sampleinfo\$Arrayname
    metadata <- data.frame(Class = sampleinfo\$Class, row.names = sampleinfo\$Arrayname)
    phenoData(AffybatchRCC) <- new("AnnotatedDataFrame", data = metadata)
    
    # Define Copy Number input files
    CNdataFile <- "CNAG_data_PREDA.txt"
    CNannotationFile <- "SNPAnnot100k.csv"
    
    # ==========================================
    # STEP 1: Preprocess Gene Expression Data
    # ==========================================
    SODEGIRGEDataForPREDA<-SODEGIRpreprocessingGE(AffyBatchInput=AffybatchRCC, custom_cdfname="hgu133plus2", classColumn="Class", referenceGroupLabel="normal", statisticType="tstatistic", optionalAnnotations=c("SYMBOL", "ENTREZID"), retain.chrs=1:22)
    
    # ==========================================
    # STEP 2: Run PREDA on Gene Expression Data
    # ==========================================
    SODEGIRGEanalysisResults<-PREDA_main(SODEGIRGEDataForPREDA)
    
    # ==========================================
    # STEP 3: Extract Significant Expression Regions
    # ==========================================
    SODEGIR_GE_UP<-PREDAResults2GenomicRegions(SODEGIRGEanalysisResults, qval.threshold=0.05, smoothStatistic.tail="upper", smoothStatistic.threshold=0.5)
    SODEGIR_GE_DOWN<-PREDAResults2GenomicRegions(SODEGIRGEanalysisResults, qval.threshold=0.05, smoothStatistic.tail="lower", smoothStatistic.threshold= -0.5)
    
    # ==========================================
    # STEP 4: Import Copy Number Statistics
    # ==========================================
    CNStatisticsForPREDA<-StatisticsForPREDAFromfile(file=CNdataFile, ids_column="AffymetrixSNPsID", testedTail="both", sep="\t", header=TRUE)
    
    # ==========================================
    # STEP 5: Import Copy Number Genomic Annotations
    # ==========================================
    CNGenomicsAnnotationsForPREDA<-GenomicAnnotationsForPREDAFromfile(file=CNannotationFile, ids_column=1, chr_column="Chromosome", start_column=4, end_column=4, strand_column="Strand", chromosomesLabelsInput=1:22, MinusStrandString="-", PlusStrandString="+", optionalAnnotationsColumns=c("Cytoband", "Entrez_gene"), header=TRUE, sep=",", quote="\"", na.strings = c("NA", "", "---"))
    
    # ==========================================
    # STEP 6: Merge Copy Number Statistics and Annotations
    # ==========================================
    SODEGIRCNDataForPREDA<-MergeStatisticAnnotations2DataForPREDA(CNStatisticsForPREDA, CNGenomicsAnnotationsForPREDA, sortAndCleanNA=TRUE, quiet=FALSE, MedianCenter=TRUE)
    
    # ==========================================
    # STEP 7: Run PREDA on Copy Number Data
    # ==========================================
    SODEGIRCNanalysisResults<-PREDA_main(SODEGIRCNDataForPREDA, outputGenomicAnnotationsForPREDA=SODEGIRGEDataForPREDA)
    
    # ==========================================
    # STEP 8: Extract Copy Number Gain and Loss Regions
    # ==========================================
    SODEGIR_CN_GAIN<-PREDAResults2GenomicRegions(SODEGIRCNanalysisResults, qval.threshold=0.01, smoothStatistic.tail="upper", smoothStatistic.threshold=0.1)
    SODEGIR_CN_LOSS<-PREDAResults2GenomicRegions(SODEGIRCNanalysisResults, qval.threshold=0.01, smoothStatistic.tail="lower", smoothStatistic.threshold= -0.1)
    
    # ==========================================
    # STEP 9: Find Overlapping Regions (Amplified/Deleted)
    # ==========================================
    SODEGIR_AMPLIFIED<-GenomicRegionsFindOverlap(SODEGIR_GE_UP, SODEGIR_CN_GAIN)
    SODEGIR_DELETED<-GenomicRegionsFindOverlap(SODEGIR_GE_DOWN, SODEGIR_CN_LOSS)
    names(SODEGIR_AMPLIFIED)<-names(SODEGIR_GE_UP)
    names(SODEGIR_DELETED)<-names(SODEGIR_GE_DOWN)
    
    # ==========================================
    # STEP 10: Plot Integrated Results
    # ==========================================
    regions_forPlot<-c(SODEGIR_GE_UP[[1]],SODEGIR_CN_GAIN[[1]],SODEGIR_AMPLIFIED[[1]],SODEGIR_GE_DOWN[[1]],SODEGIR_CN_LOSS[[1]],SODEGIR_DELETED[[1]])
    
    pdf("sodegir_genome_plot.pdf", width=12, height=8)
    checkplot<-genomePlot(SODEGIRGEanalysisResults, genomicRegions=regions_forPlot, grouping=c(1:3, 1:3), scale.positions="Mb", region.colors=c("red","red2","red4","blue","blue2","blue4"))
    legend(x=140000000, y=22*3, legend=c("GeneExpression UP","CopyNumber gain","SODEGIR amplified","GeneExpression DOWN","CopyNumber loss","SODEGIR deleted"), fill=c("red","red2","red4","blue","blue2","blue4"))
    title(paste("Sample",names(SODEGIR_GE_UP[[1]])))
    dev.off()
    
    # ==========================================
    # STEP 11: Compute Dataset-Level Signatures
    # ==========================================
    SDGsignature_amplified<-computeDatasetSignature(SODEGIRGEDataForPREDA, genomicRegionsList=SODEGIR_AMPLIFIED)
    SDGsignature_deleted<-computeDatasetSignature(SODEGIRGEDataForPREDA, genomicRegionsList=SODEGIR_DELETED)
    
    # ==========================================
    # STEP 12: Write Outputs to Files
    # ==========================================
    
    # Save RDS objects for downstream analysis
    saveRDS(SODEGIRGEanalysisResults, "SODEGIRGEanalysisResults.rds")
    saveRDS(SODEGIRCNanalysisResults, "SODEGIRCNanalysisResults.rds")
    saveRDS(SODEGIR_AMPLIFIED, "SODEGIR_AMPLIFIED.rds")
    saveRDS(SODEGIR_DELETED, "SODEGIR_DELETED.rds")
    saveRDS(SDGsignature_amplified, "SDGsignature_amplified.rds")
    saveRDS(SDGsignature_deleted, "SDGsignature_deleted.rds")
    
    # Export genomic regions to CSV format
    if (length(SODEGIR_AMPLIFIED) > 0 && !is.null(SODEGIR_AMPLIFIED[[1]])) {
        df_amp <- GenomicRegions2dataframe(SODEGIR_AMPLIFIED[[1]])
        write.csv(df_amp, "SODEGIR_AMPLIFIED_sample1.csv", row.names=FALSE)
    }
    
    if (length(SODEGIR_DELETED) > 0 && !is.null(SODEGIR_DELETED[[1]])) {
        df_del <- GenomicRegions2dataframe(SODEGIR_DELETED[[1]])
        write.csv(df_del, "SODEGIR_DELETED_sample1.csv", row.names=FALSE)
    }
    
    if (length(SDGsignature_amplified) > 0 && !is.null(SDGsignature_amplified[[1]])) {
        df_sig_amp <- GenomicRegions2dataframe(SDGsignature_amplified[[1]])
        write.csv(df_sig_amp, "SDGsignature_amplified.csv", row.names=FALSE)
    }
    
    if (length(SDGsignature_deleted) > 0 && !is.null(SDGsignature_deleted[[1]])) {
        df_sig_del <- GenomicRegions2dataframe(SDGsignature_deleted[[1]])
        write.csv(df_sig_del, "SDGsignature_deleted.csv", row.names=FALSE)
    }

    writeLines(c(
        '"BIOC_PREDA_SODEGIR_COMBINED_ANALYSIS":',
        paste0('    PREDA: ', as.character(packageVersion('PREDA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sodegir_combined_analysis.csv versions.yml
    """
}

workflow BIOC_PREDA_SODEGIR_COMBINED_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sampleinfoGE_PREDA.txt, Raw Affymetrix .CEL files, CNAG_data_PREDA.txt, SNPAnnot100k.csv ] ]

    main:
    BIOC_PREDA_SODEGIR_COMBINED_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_PREDA_SODEGIR_COMBINED_ANALYSIS.out.tables
    plots    = BIOC_PREDA_SODEGIR_COMBINED_ANALYSIS.out.plots
    objects  = BIOC_PREDA_SODEGIR_COMBINED_ANALYSIS.out.objects
    versions = BIOC_PREDA_SODEGIR_COMBINED_ANALYSIS.out.versions
}
