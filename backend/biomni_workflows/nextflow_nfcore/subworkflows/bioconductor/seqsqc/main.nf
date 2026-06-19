#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: seqsqc — all_in_one_qc
// Run the entire sample quality control pipeline in a single step and generate a report.
// Input: example_sub.vcf, sampleAnnotation.txt, CCDS.Hs37.3.reduced_chr1.bed
// Container: quay.io/biocontainers/bioconductor-seqsqc:1.32.0--r45hdfd78af_0
// R packages: SeqSQC
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: plot (ggplot/base)

nextflow.enable.dsl = 2

process BIOC_SEQSQC_ALL_IN_ONE_QC {
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
    
    # Load the required library
    library(SeqSQC)
    
    # Define input file paths from the working directory
    infile <- "example_sub.vcf"
    sample.annot <- "sampleAnnotation.txt"
    cr <- "CCDS.Hs37.3.reduced_chr1.bed"
    
    # Define output directory and prefix
    outdir <- "."
    outfile <- file.path(outdir, "testWrapUp")
    
    # Run the all-in-one sample QC pipeline
    seqfile <- sampleQC(
        vfile = infile,
        output = outfile,
        capture.region = cr,
        sample.annot = sample.annot,
        format.data = "NGS",
        format.file = "vcf",
        QCreport = FALSE
    )
    
    # Save the resulting SeqSQC object
    save(seqfile, file="seqfile.RData")
    
    # Extract and save the problematic sample list
    probs <- problemList(seqfile)
    if (!is.null(probs\$prob.list)) {
        write.csv(probs\$prob.list, file="problematic_samples.csv", row.names=FALSE)
    }
    if (!is.null(probs\$remove.list)) {
        write.csv(probs\$remove.list, file="remove_list.csv", row.names=FALSE)
    }
    
    # Extract and save individual QC step results
    qc_res <- QCresult(seqfile)
    if (!is.null(qc_res\$MissingRate)) {
        write.csv(qc_res\$MissingRate, file="QC_MissingRate.csv", row.names=FALSE)
    }
    if (!is.null(qc_res\$SexCheck)) {
        write.csv(qc_res\$SexCheck, file="QC_SexCheck.csv", row.names=FALSE)
    }
    if (!is.null(qc_res\$Inbreeding)) {
        write.csv(qc_res\$Inbreeding, file="QC_Inbreeding.csv", row.names=FALSE)
    }
    if (!is.null(qc_res\$IBD)) {
        write.csv(qc_res\$IBD, file="QC_IBD.csv", row.names=FALSE)
    }
    if (!is.null(qc_res\$PCA)) {
        write.csv(qc_res\$PCA, file="QC_PCA.csv", row.names=FALSE)
    }
    
    # Generate and save QC plots to a PDF file
    pdf("QC_plots.pdf", width=8, height=6)
    tryCatch({
        plotQC(seqfile, QCstep = "MissingRate")
    }, error = function(e) {
        message("Could not plot MissingRate: ", e\$message)
    })
    
    tryCatch({
        plotQC(seqfile, QCstep = "SexCheck")
    }, error = function(e) {
        message("Could not plot SexCheck: ", e\$message)
    })
    
    tryCatch({
        plotQC(seqfile, QCstep = "Inbreeding")
    }, error = function(e) {
        message("Could not plot Inbreeding: ", e\$message)
    })
    
    tryCatch({
        plotQC(seqfile, QCstep = "IBD")
    }, error = function(e) {
        message("Could not plot IBD: ", e\$message)
    })
    
    tryCatch({
        plotQC(seqfile, QCstep = "PCA")
    }, error = function(e) {
        message("Could not plot PCA: ", e\$message)
    })
    dev.off()
    
    # Generate the HTML QC report
    tryCatch({
        RenderReport(seqfile, output="report.html", interactive=TRUE)
    }, error = function(e) {
        message("Could not render HTML report: ", e\$message)
    })

    writeLines(c(
        '"BIOC_SEQSQC_ALL_IN_ONE_QC":',
        paste0('        seqsqc: ', as.character(packageVersion("seqsqc")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_all_in_one_qc.csv versions.yml
    """
}

workflow BIOC_SEQSQC_ALL_IN_ONE_QC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ example_sub.vcf, sampleAnnotation.txt, CCDS.Hs37.3.reduced_chr1.bed ] ]

    main:
    BIOC_SEQSQC_ALL_IN_ONE_QC(ch_input)

    emit:
    tables   = BIOC_SEQSQC_ALL_IN_ONE_QC.out.tables
    plots    = BIOC_SEQSQC_ALL_IN_ONE_QC.out.plots
    objects  = BIOC_SEQSQC_ALL_IN_ONE_QC.out.objects
    versions = BIOC_SEQSQC_ALL_IN_ONE_QC.out.versions
}
