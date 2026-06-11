#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CRISPRseek — offtarget_search_with_bulges
// Search for off-targets allowing DNA and RNA bulges using Cas-OFFinder.
// Input: inputseq.fa
// Container: quay.io/biocontainers/bioconductor-crisprseek:1.50.0--r45hdfd78af_0
// R packages: BSgenome.Hsapiens.UCSC.hg38, CRISPRseek
// Bioconductor: 3.20 | R: 4.4
// Requires: BSgenome.Hsapiens.UCSC.hg38, CRISPRseek
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run offTargetAnalysis with findOffTargetsWithBulge = TRUE
//  * 2. [Core Analysis] Alternatively, find gRNAs first using findgRNAs and pass the result to getOfftargetWithBulge

nextflow.enable.dsl = 2

process BIOC_CRISPRSEEK_OFFTARGET_SEARCH_WITH_BULGES {
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
    .bm_deps <- c("BSgenome.Hsapiens.UCSC.hg38", "CRISPRseek")
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
    
    library(CRISPRseek)
    library(BSgenome.Hsapiens.UCSC.hg38)
    
    # Define input file from the working directory
    inputFilePath <- "inputseq.fa"
    
    # Define and create output directory
    outputDir <- "output_bulges"
    if (!dir.exists(outputDir)) {
      dir.create(outputDir, recursive = TRUE)
    }
    
    # Stage 1: Run offTargetAnalysis with findOffTargetsWithBulge = TRUE
    res1 <- offTargetAnalysis(inputFilePath = inputFilePath,
                              findOffTargetsWithBulge = TRUE,
                              BSgenomeName = Hsapiens,
                              chromToSearch = "chrX",
                              annotateExon = FALSE,
                              outputDir = outputDir,
                              overwrite = TRUE)
    
    # Print summary of the bulge search results
    print("Stage 1: offTargetAnalysis with bulges completed.")
    if (!is.null(res1\$offtarget) && nrow(res1\$offtarget) > 0) {
      cols_to_print <- intersect(c("name", "gRNAPlusPAM_bulge", "OffTargetSequence_bulge", "n.RNABulge", "n.DNABulge", "alignment"), colnames(res1\$offtarget))
      print(head(res1\$offtarget[, cols_to_print, drop = FALSE]))
    }
    
    # Save Stage 1 results
    write.csv(res1\$offtarget, file = file.path(outputDir, "offtarget_with_bulges.csv"), row.names = FALSE)
    saveRDS(res1, file = file.path(outputDir, "offtarget_analysis_res.rds"))
    
    
    # Stage 2: Alternatively, find gRNAs first using findgRNAs and pass the result to getOfftargetWithBulge
    gRNA_PAM <- findgRNAs(inputFilePath = inputFilePath,
                          pairOutputFile = file.path(outputDir, "testpairedgRNAs.xls"),
                          findPairedgRNAOnly = TRUE)
    
    res2 <- getOfftargetWithBulge(gRNA_PAM,
                                  BSgenomeName = Hsapiens, 
                                  chromToSearch = "chrX")
    
    # Print summary of Stage 2 results
    print("Stage 2: getOfftargetWithBulge completed.")
    print(head(res2))
    
    # Save Stage 2 results
    write.csv(res2, file = file.path(outputDir, "getOfftargetWithBulge_res.csv"), row.names = FALSE)
    saveRDS(res2, file = file.path(outputDir, "getOfftargetWithBulge_res.rds"))

    writeLines(c(
        '"BIOC_CRISPRSEEK_OFFTARGET_SEARCH_WITH_BULGES":',
        paste0('    CRISPRseek: ', as.character(packageVersion('CRISPRseek')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_offtarget_search_with_bulges.csv versions.yml
    """
}

workflow BIOC_CRISPRSEEK_OFFTARGET_SEARCH_WITH_BULGES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ inputseq.fa ] ]

    main:
    BIOC_CRISPRSEEK_OFFTARGET_SEARCH_WITH_BULGES(ch_input)

    emit:
    tables   = BIOC_CRISPRSEEK_OFFTARGET_SEARCH_WITH_BULGES.out.tables
    plots    = BIOC_CRISPRSEEK_OFFTARGET_SEARCH_WITH_BULGES.out.plots
    objects  = BIOC_CRISPRSEEK_OFFTARGET_SEARCH_WITH_BULGES.out.objects
    versions = BIOC_CRISPRSEEK_OFFTARGET_SEARCH_WITH_BULGES.out.versions
}
