#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: hapfabia — vcf_pipeline
// Convert a VCF file to sparse matrix format, split it into overlapping intervals, run iterative FABIA, identify duplicates, and analyze/plot the resulting IBD se
// Input: filename.vcf
// Container: quay.io/biocontainers/bioconductor-hapfabia:1.52.0--r45h01b2380_0
// R packages: hapFabia
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_HAPFABIA_VCF_PIPELINE {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-hapfabia:1.52.0--r45h01b2380_0"

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
    .bm_deps <- c("hapFabia")
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
    
    # hapfabia VCF Pipeline
    # This script converts a VCF file to sparse matrix format, splits it into overlapping intervals,
    # runs iterative FABIA, identifies duplicates, and analyzes/plots the resulting IBD segments.
    
    # Define intervals, overlap, and filename
    shiftSize <- 5000
    intervalSize <- 10000
    fileName <- "filename" # without type (expects filename.vcf in the working directory)
    
    # Load required library
    library(hapFabia)
    
    # --- Convert VCF to sparse matrix format ---
    vcftoFABIA(fileName=fileName)
    
    # --- Copy genotype matrix to the active matrix file ---
    file.copy(paste(fileName,"_matG.txt",sep=""),
              paste(fileName,"_mat.txt",sep=""),
              overwrite = TRUE)
    
    # --- Split the sparse matrix into overlapping intervals ---
    split_sparse_matrix(fileName=fileName,intervalSize=intervalSize,
                        shiftSize=shiftSize,annotation=TRUE)
    
    # Compute how many intervals we have
    ina <- as.numeric(readLines(paste(fileName,"_mat.txt",sep=""),n=2))
    noSNVs <- ina[2]
    over <- intervalSize%/%shiftSize
    N1 <- noSNVs%/%shiftSize
    endRunA <- (N1-over+2)
    
    # --- Run iterative FABIA across intervals ---
    iterateIntervals(startRun=1,endRun=endRunA,shift=shiftSize,
                     intervalSize=intervalSize,fileName=fileName,individuals=0,
                     upperBP=0.05,p=10,iter=40,alpha=0.03,cyc=50,IBDsegmentLength=50,
                     Lt = 0.1,Zt = 0.2,thresCount=1e-5,mintagSNVsFactor=3/4,
                     pMAF=0.035,haplotypes=FALSE,cut=0.8,procMinIndivids=0.1,thresPrune=1e-3,
                     simv="minD",minTagSNVs=6,minIndivid=2,avSNVsDist=100,SNVclusterLength=100)
    
    # --- Identify duplicate IBD segments across overlapping ---
    identifyDuplicates(fileName=fileName,startRun=1,endRun=endRunA,
                       shift=shiftSize,intervalSize=intervalSize)
    
    # --- Analyze the non-duplicate IBD segments ---
    anaRes <- analyzeIBDsegments(fileName=fileName,startRun=1,endRun=endRunA,
                                 shift=shiftSize,intervalSize=intervalSize)
    
    # Save analysis results to disk
    saveRDS(anaRes, file="analysis_results.rds")
    
    # --- Load and plot specific IBD segments ---
    # Select a valid interval index (robust fallback if endRunA is small)
    posAll <- min(50, max(1, endRunA - 1))
    start <- (posAll-1)*shiftSize
    end <- start + intervalSize
    pRange <- paste("_",format(start,scientific=FALSE),"_",
                    format(end,scientific=FALSE),sep="")
    
    rda_file <- paste(fileName,pRange,"_resAnno",".Rda",sep="")
    
    if (file.exists(rda_file)) {
        load(file=rda_file)
        IBDsegmentList <- resHapFabia\$mergedIBDsegmentList
    
        summary(IBDsegmentList)
        
        # Plot the entire IBD segment list for this interval
        tryCatch({
            plot(IBDsegmentList,filename=paste(fileName,pRange,"_mat",sep=""))
        }, error = function(e) {
            message("Could not plot IBDsegmentList: ", e\$message)
        })
    
        # Plot the first individual IBD segment if available
        if (length(IBDsegmentList) > 0) {
            IBDsegment <- IBDsegmentList[[1]]
            tryCatch({
                plot(IBDsegment,filename=paste(fileName,pRange,"_mat",sep=""))
            }, error = function(e) {
                message("Could not plot individual IBDsegment: ", e\$message)
            })
        }
    } else {
        message("No results found for interval index: ", posAll, " (File not found: ", rda_file, ")")
    }

    writeLines(c(
        '"BIOC_HAPFABIA_VCF_PIPELINE":',
        paste0('        hapfabia: ', as.character(packageVersion("hapfabia")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_vcf_pipeline.csv versions.yml
    """
}

workflow BIOC_HAPFABIA_VCF_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ filename.vcf ] ]

    main:
    BIOC_HAPFABIA_VCF_PIPELINE(ch_input)

    emit:
    tables   = BIOC_HAPFABIA_VCF_PIPELINE.out.tables
    plots    = BIOC_HAPFABIA_VCF_PIPELINE.out.plots
    objects  = BIOC_HAPFABIA_VCF_PIPELINE.out.objects
    versions = BIOC_HAPFABIA_VCF_PIPELINE.out.versions
}
