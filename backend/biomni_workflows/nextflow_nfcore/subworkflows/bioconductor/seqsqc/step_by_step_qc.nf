#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: seqsqc — step_by_step_qc
// Run individual sample quality control steps sequentially to allow customization or skipping of specific checks.
// Input: example_sub.vcf, sampleAnnotation.txt, CCDS.Hs37.3.reduced_chr1.bed
// Container: quay.io/biocontainers/bioconductor-seqsqc:1.32.0--r45hdfd78af_0
// R packages: SeqSQC
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SEQSQC_STEP_BY_STEP_QC {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-seqsqc:1.32.0--r45hdfd78af_0"

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
    .bm_deps <- c("SeqSQC")
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
    
    # Load the required library
    library(SeqSQC)
    
    # Define input file paths from the working directory
    infile <- "example_sub.vcf"
    sample.annot <- "sampleAnnotation.txt"
    cr <- "CCDS.Hs37.3.reduced_chr1.bed"
    
    # Define output directory and prefix
    outdir <- "."
    outfile <- file.path(outdir, "testWrapUp")
    
    # 1. Convert VCF to GDS and create SeqSQC object
    seqfile <- LoadVfile(vfile = infile, output = outfile, capture.region = cr, sample.annot = sample.annot)
    
    # 2. Check missing rate
    seqfile <- MissingRate(seqfile, remove.samples=NULL)
    pdf("plot_MissingRate.pdf")
    plotQC(seqfile, QCstep = "MissingRate")
    dev.off()
    
    # Save missing rate results
    res.mr <- QCresult(seqfile)\$MissingRate
    write.csv(res.mr, "missing_rate_results.csv", row.names = FALSE)
    
    # 3. Check sex discordance
    seqfile <- SexCheck(seqfile, remove.samples=NULL)
    pdf("plot_SexCheck.pdf")
    plotQC(seqfile, QCstep = "SexCheck")
    dev.off()
    
    # Save sex check results
    res.sexc <- QCresult(seqfile)\$SexCheck
    write.csv(res.sexc, "sex_check_results.csv", row.names = FALSE)
    
    # 4. Check inbreeding coefficient
    seqfile <- Inbreeding(seqfile, remove.samples=NULL)
    pdf("plot_Inbreeding.pdf")
    plotQC(seqfile, QCstep = "Inbreeding")
    dev.off()
    
    # Save inbreeding results
    res.inb <- QCresult(seqfile)\$Inbreeding
    write.csv(res.inb, "inbreeding_results.csv", row.names = FALSE)
    
    # 5. Check identity-by-descent (IBD)
    seqfile <- IBD(seqfile, remove.samples=NULL)
    pdf("plot_IBD.pdf")
    plotQC(seqfile, QCstep = "IBD")
    dev.off()
    
    # Save IBD results
    res.ibd <- QCresult(seqfile)\$IBD
    write.csv(res.ibd, "ibd_results.csv", row.names = FALSE)
    
    # 6. Check population outliers (PCA)
    seqfile <- PCA(seqfile, remove.samples=NULL)
    pdf("plot_PCA.pdf")
    plotQC(seqfile, QCstep = "PCA")
    dev.off()
    
    # Save PCA results
    res.pca <- QCresult(seqfile)\$PCA
    write.csv(res.pca, "pca_results.csv", row.names = FALSE)
    
    # Run interactive PCA plot as documented
    p_interactive <- plotQC(seqfile, QCstep = "PCA", interactive=TRUE)
    if (requireNamespace("htmlwidgets", quietly = TRUE)) {
      tryCatch({
        htmlwidgets::saveWidget(p_interactive, "plot_PCA_interactive.html")
      }, error = function(e) {
        warning("Could not save interactive PCA plot: ", e\$message)
      })
    }
    
    # 7. Extract problematic samples
    probs <- problemList(seqfile)
    write.csv(probs\$prob.list, "problematic_samples.csv", row.names = FALSE)
    write.csv(probs\$remove.list, "remove_list.csv", row.names = FALSE)
    
    # Save the SeqSQC object
    save(seqfile, file="seqfile.Rdata")
    
    # 8. Generate HTML report
    RenderReport(seqfile, output="report.html", interactive=TRUE)

    cat <<-END_VERSIONS > versions.yml
    "BIOC_SEQSQC_STEP_BY_STEP_QC":
        seqsqc: \$(Rscript -e 'cat(as.character(packageVersion("seqsqc")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_step_by_step_qc.csv versions.yml
    """
}

workflow BIOC_SEQSQC_STEP_BY_STEP_QC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ example_sub.vcf, sampleAnnotation.txt, CCDS.Hs37.3.reduced_chr1.bed ] ]

    main:
    BIOC_SEQSQC_STEP_BY_STEP_QC(ch_input)

    emit:
    tables   = BIOC_SEQSQC_STEP_BY_STEP_QC.out.tables
    plots    = BIOC_SEQSQC_STEP_BY_STEP_QC.out.plots
    objects  = BIOC_SEQSQC_STEP_BY_STEP_QC.out.objects
    versions = BIOC_SEQSQC_STEP_BY_STEP_QC.out.versions
}
