#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: crisprseek — bulge_offtarget_analysis
// Search for off-targets allowing DNA and RNA bulges using Cas-OFFinder.
// Input: inputseq.fa
// Container: quay.io/biocontainers/bioconductor-crisprseek:1.50.0--r45hdfd78af_0
// R packages: BSgenome.Hsapiens.UCSC.hg38, CRISPRseek
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CRISPRSEEK_BULGE_OFFTARGET_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-crisprseek:1.50.0--r45hdfd78af_0"

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
    
    # Define input file and output directory
    inputFilePath <- "inputseq.fa"
    outputDir <- getwd()
    
    # Stage 1: Run offTargetAnalysis with findOffTargetsWithBulge = TRUE
    message("Stage 1: Running offTargetAnalysis with bulge search...")
    res1 <- tryCatch({
      offTargetAnalysis(inputFilePath = inputFilePath,
                        findOffTargetsWithBulge = TRUE,
                        BSgenomeName = Hsapiens,
                        chromToSearch = "chrX",
                        annotateExon = FALSE,
                        outputDir = outputDir,
                        overwrite = TRUE)
    }, error = function(e) {
      message("Error or warning during offTargetAnalysis: ", e\$message)
      NULL
    })
    
    # Save Stage 1 results if successful
    if (!is.null(res1)) {
      saveRDS(res1, file = "offTargetAnalysis_bulge_res.rds")
      if (!is.null(res1\$offtarget)) {
        write.csv(res1\$offtarget, file = "offtarget_bulge.csv", row.names = FALSE)
        print(head(res1\$offtarget[, c("name", "gRNAPlusPAM_bulge", "OffTargetSequence_bulge", "n.RNABulge", "n.DNABulge", "alignment")]))
      }
    }
    
    # Stage 2: Find gRNAs first using findgRNAs and then call getOfftargetWithBulge
    message("Stage 2: Running findgRNAs and getOfftargetWithBulge...")
    gRNA_PAM <- tryCatch({
      findgRNAs(inputFilePath = inputFilePath,
                pairOutputFile = "testpairedgRNAs.xls",
                findPairedgRNAOnly = TRUE)
    }, error = function(e) {
      message("Error or warning during findgRNAs: ", e\$message)
      NULL
    })
    
    if (!is.null(gRNA_PAM)) {
      saveRDS(gRNA_PAM, file = "gRNA_PAM.rds")
      
      res2 <- tryCatch({
        getOfftargetWithBulge(gRNA_PAM,
                              BSgenomeName = Hsapiens, 
                              chromToSearch = "chrX")
      }, error = function(e) {
        message("Error or warning during getOfftargetWithBulge: ", e\$message)
        NULL
      })
      
      # Save Stage 2 results if successful
      if (!is.null(res2)) {
        saveRDS(res2, file = "getOfftargetWithBulge_res.rds")
        write.csv(res2, file = "offtarget_with_bulge_direct.csv", row.names = FALSE)
        print(head(res2))
      }
    }

    writeLines(c(
        '"BIOC_CRISPRSEEK_BULGE_OFFTARGET_ANALYSIS":',
        paste0('        crisprseek: ', as.character(packageVersion("crisprseek")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bulge_offtarget_analysis.csv versions.yml
    """
}

workflow BIOC_CRISPRSEEK_BULGE_OFFTARGET_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ inputseq.fa ] ]

    main:
    BIOC_CRISPRSEEK_BULGE_OFFTARGET_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_CRISPRSEEK_BULGE_OFFTARGET_ANALYSIS.out.tables
    plots    = BIOC_CRISPRSEEK_BULGE_OFFTARGET_ANALYSIS.out.plots
    objects  = BIOC_CRISPRSEEK_BULGE_OFFTARGET_ANALYSIS.out.objects
    versions = BIOC_CRISPRSEEK_BULGE_OFFTARGET_ANALYSIS.out.versions
}
