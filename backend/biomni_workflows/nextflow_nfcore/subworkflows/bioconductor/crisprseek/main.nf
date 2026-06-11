#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: crisprseek — standard_offtarget_analysis
// Identify gRNAs in an input sequence, perform off-target analysis against a reference genome, and annotate off-targets.
// Input: inputseq.fa
// Container: quay.io/biocontainers/bioconductor-crisprseek:1.50.0--r45hdfd78af_0
// R packages: BSgenome.Hsapiens.UCSC.hg38, TxDb.Hsapiens.UCSC.hg38.knownGene, CRISPRseek, org.Hs.eg.db
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CRISPRSEEK_STANDARD_OFFTARGET_ANALYSIS {
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
    .bm_deps <- c("BSgenome.Hsapiens.UCSC.hg38", "TxDb.Hsapiens.UCSC.hg38.knownGene", "CRISPRseek", "org.Hs.eg.db")
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
    
    # 1. Load required annotation and genome packages
    library(CRISPRseek)
    library(BSgenome.Hsapiens.UCSC.hg38)
    library(TxDb.Hsapiens.UCSC.hg38.knownGene)
    library(org.Hs.eg.db)
    
    # 2. Define input and output paths
    inputFilePath <- "inputseq.fa"
    outputDir <- getwd()
    
    # Verify input file exists
    if (!file.exists(inputFilePath)) {
      stop(paste("Error: Required input file '", inputFilePath, "' not found in the working directory.", sep = ""))
    }
    
    # 3. Run offTargetAnalysis with input sequence, BSgenome, TxDb, and OrgDb
    res <- offTargetAnalysis(inputFilePath = inputFilePath,
                             BSgenomeName = Hsapiens,
                             chromToSearch= "chrX", 
                             
                             # Annotation packages required for annotation.
                             txdb = TxDb.Hsapiens.UCSC.hg38.knownGene, 
                             orgAnn = org.Hs.egSYMBOL,
                             
                             outputDir = outputDir,
                             overwrite = TRUE)
    
    # Display preview of results
    cat("\n--- Summary Results Preview ---\n")
    print(head(res\$summary[, c("names", "gRNAsPlusPAM", "gRNAefficacy")]))
    
    cat("\n--- Off-target Results Preview ---\n")
    print(head(res\$offtarget[, c("name", "OffTargetSequence", "alignment", "score", "gRNAefficacy")]))
    
    # 4. Write named output files for the meaningful results
    write.csv(res\$summary, file = file.path(outputDir, "summary_results.csv"), row.names = FALSE)
    write.csv(res\$offtarget, file = file.path(outputDir, "offtarget_results.csv"), row.names = FALSE)
    saveRDS(res, file = file.path(outputDir, "offtarget_analysis_res.rds"))
    
    cat("\nAnalysis complete. Outputs saved to 'summary_results.csv', 'offtarget_results.csv', and 'offtarget_analysis_res.rds'.\n")

    writeLines(c(
        '"BIOC_CRISPRSEEK_STANDARD_OFFTARGET_ANALYSIS":',
        paste0('        crisprseek: ', as.character(packageVersion("crisprseek")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standard_offtarget_analysis.csv versions.yml
    """
}

workflow BIOC_CRISPRSEEK_STANDARD_OFFTARGET_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ inputseq.fa ] ]

    main:
    BIOC_CRISPRSEEK_STANDARD_OFFTARGET_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_CRISPRSEEK_STANDARD_OFFTARGET_ANALYSIS.out.tables
    plots    = BIOC_CRISPRSEEK_STANDARD_OFFTARGET_ANALYSIS.out.plots
    objects  = BIOC_CRISPRSEEK_STANDARD_OFFTARGET_ANALYSIS.out.objects
    versions = BIOC_CRISPRSEEK_STANDARD_OFFTARGET_ANALYSIS.out.versions
}
