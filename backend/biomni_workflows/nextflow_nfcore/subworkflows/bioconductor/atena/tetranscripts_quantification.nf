#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: atena — tetranscripts_quantification
// Quantify transposable element and gene expression jointly from RNA-seq BAM files using the TEtranscripts EM reassignment method.
// Input: *.bam, rmskLTR, gannot
// Container: quay.io/biocontainers/bioconductor-atena:1.16.1--r45hdfd78af_0
// R packages: BiocParallel, TxDb.Dmelanogaster.UCSC.dm6.ensGene, atena
// Bioconductor: 3.20 | R: 4.4
// Requires: BiocParallel, TxDb.Dmelanogaster.UCSC.dm6.ensGene, atena
// Visualizations: bar plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Retrieve and parse TE annotations using annotaTEs() and getLTRs()
//  * 2. [Input & Preparation] Load gene annotations from a TxDb object using exonsBy()
//  * 3. [Input & Preparation] Build the TEtranscripts parameter object using TEtranscriptsParam()
//  * 4. [Core Analysis] Quantify expression using qtex()

nextflow.enable.dsl = 2

process BIOC_ATENA_TETRANSCRIPTS_QUANTIFICATION {
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
    .bm_deps <- c("BiocParallel", "TxDb.Dmelanogaster.UCSC.dm6.ensGene", "atena", "SummarizedExperiment")
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
    library(atena)
    library(SummarizedExperiment)
    library(BiocParallel)
    
    # Stage 1: Retrieve and parse TE annotations using annotaTEs() and getLTRs()
    # Read rmskLTR from working directory if available, otherwise retrieve and parse
    rmskLTR_file <- list.files(pattern="^rmskLTR(\\\\.rds)?\$", full.names=TRUE)
    if (length(rmskLTR_file) > 0) {
      message("Reading rmskLTR from working directory...")
      rmskLTR <- readRDS(rmskLTR_file[1])
    } else {
      message("Retrieving and parsing TE annotations...")
      teann <- annotaTEs(genome="dm6", parsefun=OneCodeToFindThemAll, strict=FALSE,
                         insert=500, BPPARAM=SerialParam(progress=FALSE))
      rmskLTR <- getLTRs(teann, relLength=0.8, fullLength=TRUE, partial=TRUE,
                         otherLTR=TRUE)
    }
    
    # Stage 2: Load gene annotations from a TxDb object using exonsBy()
    # Read gannot from working directory if available, otherwise load from TxDb
    gannot_file <- list.files(pattern="^gannot(\\\\.rds)?\$", full.names=TRUE)
    if (length(gannot_file) > 0) {
      message("Reading gannot from working directory...")
      gannot <- readRDS(gannot_file[1])
    } else {
      message("Loading gene annotations from TxDb...")
      library(TxDb.Dmelanogaster.UCSC.dm6.ensGene)
      txdb <- TxDb.Dmelanogaster.UCSC.dm6.ensGene
      gannot <- exonsBy(txdb, by="gene")
    }
    
    # Locate BAM files in the working directory
    bamfiles <- list.files(pattern="\\\\.bam\$", full.names=TRUE)
    if (length(bamfiles) == 0) {
      stop("No BAM files found in the working directory.")
    }
    
    # Stage 3: Build the TEtranscripts parameter object using TEtranscriptsParam()
    ttpar <- TEtranscriptsParam(bamfiles, 
                                teFeatures=rmskLTR,
                                geneFeatures=gannot,
                                singleEnd=TRUE, 
                                ignoreStrand=TRUE, 
                                aggregateby="repName")
    
    # Stage 4: Quantify expression using qtex()
    ttq <- qtex(ttpar)
    
    # Write outputs
    saveRDS(ttq, "ttq_results.rds")
    write.csv(assay(ttq), "ttq_counts.csv", row.names=TRUE)
    
    # Generate a summary plot
    pdf("quantification_summary.pdf")
    barplot(colSums(assay(ttq)), 
            main="Total Quantified Counts per Sample", 
            col="skyblue", 
            las=1, 
            ylab="Counts")
    dev.off()
    
    message("Pipeline completed successfully. Outputs written to 'ttq_results.rds', 'ttq_counts.csv', and 'quantification_summary.pdf'.")

    writeLines(c(
        '"BIOC_ATENA_TETRANSCRIPTS_QUANTIFICATION":',
        paste0('    atena: ', as.character(packageVersion('atena')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tetranscripts_quantification.csv versions.yml
    """
}

workflow BIOC_ATENA_TETRANSCRIPTS_QUANTIFICATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ *.bam, rmskLTR, gannot ] ]

    main:
    BIOC_ATENA_TETRANSCRIPTS_QUANTIFICATION(ch_input)

    emit:
    tables   = BIOC_ATENA_TETRANSCRIPTS_QUANTIFICATION.out.tables
    plots    = BIOC_ATENA_TETRANSCRIPTS_QUANTIFICATION.out.plots
    objects  = BIOC_ATENA_TETRANSCRIPTS_QUANTIFICATION.out.objects
    versions = BIOC_ATENA_TETRANSCRIPTS_QUANTIFICATION.out.versions
}
