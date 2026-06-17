#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: EBSeq — isoform_de_two_conditions
// Identify differentially expressed isoforms between two biological conditions while accounting for isoform estimation uncertainty.
// Input: isoform_counts.csv, isoform_annotations.csv, sample_conditions.csv
// Container: quay.io/biocontainers/bioconductor-ebseq:2.8.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: EBSeq
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Read User Input Files
//  * 2. [Core Analysis] Run EBSeq Pipeline (reproducing documented code
//  * 3. [Core Analysis] Diagnostics and Plots
//  * 4. [Core Analysis] Write Outputs

nextflow.enable.dsl = 2

process BIOC_EBSEQ_ISOFORM_DE_TWO_CONDITIONS {
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
    .bm_deps <- c("EBSeq")
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
    
    # Load required library
    library(EBSeq)
    
    # --- Read User Input Files ---
    # isoform_counts.csv: Matrix of raw isoform counts (rows = isoforms, columns = samples)
    IsoMat_df <- read.csv("isoform_counts.csv", row.names = 1, check.names = FALSE)
    IsoMat <- as.matrix(IsoMat_df)
    
    # isoform_annotations.csv: Isoform names and parent gene names
    IsoAnno <- read.csv("isoform_annotations.csv", stringsAsFactors = FALSE)
    IsoNames <- as.character(IsoAnno[[1]])
    IsosGeneNames <- as.character(IsoAnno[[2]])
    
    # sample_conditions.csv: Vector indicating the condition of each sample
    SampleConds <- read.csv("sample_conditions.csv", stringsAsFactors = FALSE)
    Conditions <- as.factor(SampleConds[[1]])
    
    # --- Run EBSeq Pipeline (reproducing documented code ---
    IsoSizes=MedianNorm(IsoMat)
    NgList=GetNg(IsoNames, IsosGeneNames)
    IsoNgTrun=NgList\$IsoformNgTrun
    
    IsoEBOut=EBTest(Data=IsoMat, NgVector=IsoNgTrun, Conditions=Conditions, sizeFactors=IsoSizes, maxround=5)
    IsoEBDERes=GetDEResults(IsoEBOut, FDR=0.05)
    IsoFC=PostFC(IsoEBOut)
    
    # Print parameter estimates to stdout
    cat("Alpha parameter estimates:\n")
    print(IsoEBOut\$Alpha)
    cat("\nBeta parameter estimates:\n")
    print(IsoEBOut\$Beta)
    cat("\nP parameter estimates:\n")
    print(IsoEBOut\$P)
    
    # --- Diagnostics and Plots ---
    pdf("ebseq_diagnostics.pdf", width = 10, height = 8)
    par(mfrow = c(2, 3))
    
    PolyFitValue=vector("list",3)
    for(i in 1:3) {
        tryCatch({
            PolyFitValue[[i]]=PolyFitPlot(IsoEBOut\$C1Mean[[i]], IsoEBOut\$C1EstVar[[i]], 5)
        }, error = function(e) {
            warning("Could not plot PolyFitPlot for group ", i, ": ", e\$message)
        })
    }
    
    tryCatch({
        QQP(IsoEBOut)
    }, error = function(e) {
        warning("Could not plot QQP: ", e\$message)
    })
    
    tryCatch({
        DenNHist(IsoEBOut)
    }, error = function(e) {
        warning("Could not plot DenNHist: ", e\$message)
    })
    
    dev.off()
    
    # --- Write Outputs ---
    # Save RDS objects
    saveRDS(IsoEBOut, "IsoEBOut.rds")
    saveRDS(IsoEBDERes, "IsoEBDERes.rds")
    
    # Save CSV tables
    write.csv(IsoEBDERes\$PPMat, "isoform_posterior_probabilities.csv", row.names = TRUE)
    
    # Status table
    status_df <- data.frame(
        Isoform = names(IsoEBDERes\$Status),
        Status = IsoEBDERes\$Status,
        stringsAsFactors = FALSE
    )
    write.csv(status_df, "isoform_de_status.csv", row.names = FALSE)
    
    # DE found list
    write.table(IsoEBDERes\$DEfound, "de_isoforms.txt", row.names = FALSE, col.names = FALSE, quote = FALSE)
    
    # Fold changes
    fc_df <- data.frame(
        Isoform = names(IsoFC\$PostFC),
        PostFC = IsoFC\$PostFC,
        RealFC = IsoFC\$RealFC,
        stringsAsFactors = FALSE
    )
    write.csv(fc_df, "isoform_fold_changes.csv", row.names = FALSE)
    
    cat("\nPipeline completed successfully. Outputs written to working directory.\n")

    writeLines(c(
        '"BIOC_EBSEQ_ISOFORM_DE_TWO_CONDITIONS":',
        paste0('    EBSeq: ', as.character(packageVersion('EBSeq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_isoform_de_two_conditions.csv versions.yml
    """
}

workflow BIOC_EBSEQ_ISOFORM_DE_TWO_CONDITIONS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ isoform_counts.csv, isoform_annotations.csv, sample_conditions.csv ] ]

    main:
    BIOC_EBSEQ_ISOFORM_DE_TWO_CONDITIONS(ch_input)

    emit:
    tables   = BIOC_EBSEQ_ISOFORM_DE_TWO_CONDITIONS.out.tables
    plots    = BIOC_EBSEQ_ISOFORM_DE_TWO_CONDITIONS.out.plots
    objects  = BIOC_EBSEQ_ISOFORM_DE_TWO_CONDITIONS.out.objects
    versions = BIOC_EBSEQ_ISOFORM_DE_TWO_CONDITIONS.out.versions
}
