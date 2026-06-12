#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: IVAS — sqtl_mapping_workflow
// Identify genetic variants (sQTLs) affecting alternative splicing patterns from paired genotype and transcript expression data.
// Input: genotype_matrix.txt, expression_matrix.txt, snp_locus.txt, transcript_model.gtf
// Container: quay.io/biocontainers/bioconductor-ivas:2.30.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicFeatures, IVAS
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the required libraries and input datasets (genotype, expression, SNP positions, and TxDb object)
//  * 2. [Core Analysis] Identify alternative splicing events from the transcript model using Splicingfinder
//  * 3. [Core Analysis] Calculate the expression ratio of alternative splicing exons from transcript FPKM values using RatioFromFPKM
//  * 4. [Core Analysis] Identify significant sQTLs associated with alternative splicing ratios using sQTLsFinder
//  * 5. [Visualization & Output] Visualize the sQTL results as boxplots using saveBplot

nextflow.enable.dsl = 2

process BIOC_IVAS_SQTL_MAPPING_WORKFLOW {
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
    .bm_deps <- c("IVAS", "GenomicFeatures")
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
    library(IVAS)
    library(GenomicFeatures)
    
    # 1. Load the required input datasets from the working directory
    # Create TxDb object from the GTF file
    sample.Txdb <- makeTxDbFromGFF("transcript_model.gtf", format="gtf")
    
    # Read expression matrix (transcripts as rows, individuals as columns)
    sampleexp <- as.matrix(read.table("expression_matrix.txt", header=TRUE, row.names=1, sep="\t", check.names=FALSE))
    
    # Read genotype matrix (SNPs as rows, individuals as columns)
    samplesnp <- as.matrix(read.table("genotype_matrix.txt", header=TRUE, row.names=1, sep="\t", check.names=FALSE))
    
    # Read SNP locus data frame (columns: SNP, CHR, locus)
    samplesnplocus <- read.table("snp_locus.txt", header=TRUE, sep="\t", stringsAsFactors=FALSE, check.names=FALSE)
    
    # 2. Identify alternative splicing events from the transcript model using Splicingfinder
    ASdb <- Splicingfinder(GTFdb=sample.Txdb,calGene=NULL,Ncor=1,out.dir=NULL)
    
    # Determine the CalIndex dynamically to avoid failure if "ASS7" is not present in the user's custom GTF
    ass_models <- slot(ASdb, "SplicingModel")\$ASS
    cal_index <- "ASS7"
    if (!is.null(ass_models) && nrow(ass_models) > 0) {
      if (!"ASS7" %in% ass_models\$Index) {
        cal_index <- ass_models\$Index[1]
      }
    }
    
    # 3. Calculate the expression ratio of alternative splicing exons from transcript FPKM values using RatioFromFPKM
    ASdb <- RatioFromFPKM(GTFdb=sample.Txdb,ASdb=ASdb,Total.expdata=sampleexp,
        CalIndex=cal_index,Ncor=1,out.dir=NULL)
    
    # 4. Identify significant sQTLs associated with alternative splicing ratios using sQTLsFinder
    ASdb <- sQTLsFinder(ASdb=ASdb,Total.snpdata=samplesnp,
        Total.snplocus=samplesnplocus,method="lm",Ncor=1)
    
    # 5. Visualize the sQTL results as boxplots using saveBplot
    if (!dir.exists("./result")) {
      dir.create("./result", recursive=TRUE)
    }
    saveBplot(ASdb=ASdb,Total.snpdata=samplesnp,Total.snplocus=samplesnplocus,
        CalIndex=cal_index,out.dir="./result")
    
    # Save meaningful outputs
    saveRDS(ASdb, "ASdb_final.rds")
    
    # Export sQTL results to CSV if they exist
    sqtls_ass <- slot(ASdb, "sQTLs")\$ASS
    sqtls_es <- slot(ASdb, "sQTLs")\$ES
    sqtls_ir <- slot(ASdb, "sQTLs")\$IR
    
    if (!is.null(sqtls_ass) && nrow(sqtls_ass) > 0) {
      write.csv(as.data.frame(sqtls_ass), "sqtls_results_ASS.csv", row.names=FALSE)
    }
    if (!is.null(sqtls_es) && nrow(sqtls_es) > 0) {
      write.csv(as.data.frame(sqtls_es), "sqtls_results_ES.csv", row.names=FALSE)
    }
    if (!is.null(sqtls_ir) && nrow(sqtls_ir) > 0) {
      write.csv(as.data.frame(sqtls_ir), "sqtls_results_IR.csv", row.names=FALSE)
    }

    writeLines(c(
        '"BIOC_IVAS_SQTL_MAPPING_WORKFLOW":',
        paste0('    IVAS: ', as.character(packageVersion('IVAS')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sqtl_mapping_workflow.csv versions.yml
    """
}

workflow BIOC_IVAS_SQTL_MAPPING_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ genotype_matrix.txt, expression_matrix.txt, snp_locus.txt, transcript_model.gtf ] ]

    main:
    BIOC_IVAS_SQTL_MAPPING_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_IVAS_SQTL_MAPPING_WORKFLOW.out.tables
    plots    = BIOC_IVAS_SQTL_MAPPING_WORKFLOW.out.plots
    objects  = BIOC_IVAS_SQTL_MAPPING_WORKFLOW.out.objects
    versions = BIOC_IVAS_SQTL_MAPPING_WORKFLOW.out.versions
}
