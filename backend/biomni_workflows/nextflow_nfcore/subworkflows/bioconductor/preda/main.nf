#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: PREDA — diff_expressed_regions
// Identify chromosomal regions with significant localized up- or down-regulation of gene expression.
// Input: sampleinfoGE_PREDA.txt, Raw Affymetrix .CEL files or an ExpressionSet object
// Container: quay.io/biocontainers/bioconductor-preda:1.56.0--r45hdfd78af_0
// R packages: affy, annot_pkg, PREDA
// Bioconductor: 3.20 | R: 4.4
// Requires: PREDA, affy
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Compute differential expression statistics from an ExpressionSet using statisticsForPREDAfromEset. 2. Retrieve genomic annotations

nextflow.enable.dsl = 2

process BIOC_PREDA_DIFF_EXPRESSED_REGIONS {
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
    .bm_deps <- c("affy", "annot_pkg", "PREDA")
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
    
    # Load required Bioconductor and CRAN libraries
    library(PREDA)
    library(affy)
    
    # ==========================================
    # 1. USER INPUT & DATA LOADING
    # ==========================================
    
    # Read the sample metadata file
    if (!file.exists("sampleinfoGE_PREDA.txt")) {
      stop("Required input file 'sampleinfoGE_PREDA.txt' not found in the working directory.")
    }
    sampleinfo <- read.table("sampleinfoGE_PREDA.txt", sep="\t", header=TRUE, stringsAsFactors=FALSE)
    
    # Load the ExpressionSet object or preprocess raw CEL files
    ExpressionSetRCC <- NULL
    
    if (file.exists("ExpressionSetRCC.rds")) {
      ExpressionSetRCC <- readRDS("ExpressionSetRCC.rds")
    } else if (file.exists("ExpressionSetRCC.RData")) {
      env <- new.env()
      load("ExpressionSetRCC.RData", envir = env)
      objs <- ls(env)
      if ("ExpressionSetRCC" %in% objs) {
        ExpressionSetRCC <- env\$ExpressionSetRCC
      } else if (length(objs) > 0) {
        ExpressionSetRCC <- env[[objs[1]]]
      }
    }
    
    # If no pre-existing ExpressionSet is found, attempt to build it from raw CEL files
    if (is.null(ExpressionSetRCC)) {
      cel_files <- sampleinfo\$Arrayname
      if (all(file.exists(cel_files))) {
        ExpressionSetRCC <- justRMA(filenames=cel_files, sampleNames=sampleinfo\$Samplename)
      } else {
        # Fallback to any CEL files in the current directory
        local_cels <- list.files(pattern = "\\\\.[cC][eE][lL]\$")
        if (length(local_cels) > 0) {
          ExpressionSetRCC <- justRMA(filenames=local_cels)
        } else {
          stop("Could not find ExpressionSetRCC.rds/RData or the CEL files specified in sampleinfoGE_PREDA.txt.")
        }
      }
    }
    
    # Ensure the corresponding annotation package is loaded
    annot_pkg <- paste0(annotation(ExpressionSetRCC), ".db")
    if (requireNamespace(annot_pkg, quietly = TRUE)) {
      library(annot_pkg, character.only = TRUE)
    }
    
    # ==========================================
    # 2. PREDA WORKFLOW (DOCUMENTED CODE)
    # ==========================================
    
    GEstatisticsForPREDA<-statisticsForPREDAfromEset(ExpressionSetRCC, statisticType="tstatistic", referenceGroupLabel="normal", classVector=sampleinfo[,"Class"])
    GEGenomicAnnotations<-eset2GenomicAnnotations(ExpressionSetRCC, retain.chrs=1:22)
    GEGenomicAnnotationsForPREDA<-GenomicAnnotations2GenomicAnnotationsForPREDA(GEGenomicAnnotations, reference_position_type="median")
    GEDataForPREDA<-MergeStatisticAnnotations2DataForPREDA(GEstatisticsForPREDA, GEGenomicAnnotationsForPREDA, sortAndCleanNA=TRUE)
    GEanalysisResults<-PREDA_main(GEDataForPREDA)
    genomic_regions_UP<-PREDAResults2GenomicRegions(GEanalysisResults, qval.threshold=0.05, smoothStatistic.tail="upper", smoothStatistic.threshold=0.5)
    genomic_regions_DOWN<-PREDAResults2GenomicRegions(GEanalysisResults, qval.threshold=0.05, smoothStatistic.tail="lower", smoothStatistic.threshold=(-0.5))
    dataframe_UPregions<-GenomicRegions2dataframe(genomic_regions_UP[[1]])
    
    # ==========================================
    # 3. OUTPUT GENERATION & EXPORT
    # ==========================================
    
    # Save the identified genomic regions as CSV tables
    write.csv(dataframe_UPregions, "dataframe_UPregions.csv", row.names=FALSE)
    
    tryCatch({
      dataframe_DOWNregions <- GenomicRegions2dataframe(genomic_regions_DOWN[[1]])
      write.csv(dataframe_DOWNregions, "dataframe_DOWNregions.csv", row.names=FALSE)
    }, error = function(e) {
      warning("Could not export DOWN-regulated regions: ", e\$message)
    })
    
    # Save the core analysis results object
    saveRDS(GEanalysisResults, "GEanalysisResults.rds")
    
    # Plot the significant regions along the chromosomes and save to PDF
    pdf("genome_plot.pdf", width=12, height=8)
    checkplot<-genomePlot(GEanalysisResults, genomicRegions=c(genomic_regions_UP, genomic_regions_DOWN), grouping=c(1, 1), scale.positions="Mb", region.colors=c("red","blue"))
    legend(x=140000000, y=22, legend=c("UP", "DOWN"), fill=c("red","blue"))
    dev.off()

    writeLines(c(
        '"BIOC_PREDA_DIFF_EXPRESSED_REGIONS":',
        paste0('    PREDA: ', as.character(packageVersion('PREDA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_diff_expressed_regions.csv versions.yml
    """
}

workflow BIOC_PREDA_DIFF_EXPRESSED_REGIONS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sampleinfoGE_PREDA.txt, Raw Affymetrix .CEL files or an ExpressionSet object ] ]

    main:
    BIOC_PREDA_DIFF_EXPRESSED_REGIONS(ch_input)

    emit:
    tables   = BIOC_PREDA_DIFF_EXPRESSED_REGIONS.out.tables
    plots    = BIOC_PREDA_DIFF_EXPRESSED_REGIONS.out.plots
    objects  = BIOC_PREDA_DIFF_EXPRESSED_REGIONS.out.objects
    versions = BIOC_PREDA_DIFF_EXPRESSED_REGIONS.out.versions
}
