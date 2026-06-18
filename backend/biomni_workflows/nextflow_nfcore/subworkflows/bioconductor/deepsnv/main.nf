#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: deepsnv — pairwise_deepsnv
// Call subclonal single nucleotide variants by comparing a single test BAM file to a matched control BAM file.
// Input: test.bam, control.bam
// Container: quay.io/biocontainers/bioconductor-deepsnv:1.56.0--r45ha27e39d_0
// R packages: Rsamtools, deepSNV, RColorBrewer
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: plot (ggplot/base)

nextflow.enable.dsl = 2

process BIOC_DEEPSNV_PAIRWISE_DEEPSNV {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-deepsnv:1.56.0--r45ha27e39d_0"

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
    .bm_deps <- c("Rsamtools", "deepSNV", "RColorBrewer")
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
    library(deepSNV)
    library(Rsamtools)
    
    # === 1. Define genomic regions of interest ===
    # Dynamically extract the first chromosome and a reasonable region from the test BAM file
    test_bam <- "test.bam"
    control_bam <- "control.bam"
    
    if (!file.exists(test_bam)) {
      stop("Error: test.bam not found in the working directory.")
    }
    if (!file.exists(control_bam)) {
      stop("Error: control.bam not found in the working directory.")
    }
    
    header <- scanBamHeader(test_bam)
    targets <- header[[1]]\$targets
    if (length(targets) == 0) {
      stop("Error: No sequences found in the BAM header.")
    }
    
    chr_name <- names(targets)[1]
    chr_len <- targets[1]
    
    # Define the region of interest (e.g., first 5000 bp or the whole chromosome if shorter)
    regions <- data.frame(chr = chr_name, start = 1, stop = min(chr_len, 5000))
    
    # === 2. Run deepSNV to compare test and control BAM files ===
    HIVmix <- deepSNV(test = test_bam, control = control_bam, regions = regions, q = 10)
    show(HIVmix)
    
    # Safely access rows 100:110 of control and test counts
    tryCatch({
      print(control(HIVmix)[100:110, ])
    }, error = function(e) {
      message("Note: Could not subset rows 100:110 from control (fewer rows than expected). Printing head instead:")
      print(head(control(HIVmix)))
    })
    
    tryCatch({
      print(test(HIVmix)[100:110, ])
    }, error = function(e) {
      message("Note: Could not subset rows 100:110 from test (fewer rows than expected). Printing head instead:")
      print(head(test(HIVmix)))
    })
    
    # Generate and save the diagnostic plot
    pdf("deepSNV_plot.pdf")
    plot(HIVmix)
    dev.off()
    
    # === 3. Normalize the data to correct for systematic biases ===
    phiN <- normalize(HIVmix, round = TRUE)
    
    # === 4. Estimate dispersion using a beta-binomial model ===
    RCC.bb <- estimateDispersion(phiN, alternative = "two.sided")
    
    # === 5. Summarize significant SNVs ===
    SNVs <- summary(HIVmix, sig.level = 0.05, adjust.method = "BH")
    tab <- summary(RCC.bb, adjust.method = "bonferroni")[, 1:6]
    
    # Save meaningful results to files
    write.csv(SNVs, "significant_SNVs.csv", row.names = FALSE)
    write.csv(tab, "dispersion_summary.csv", row.names = TRUE)
    saveRDS(HIVmix, "HIVmix.rds")
    saveRDS(phiN, "phiN.rds")
    saveRDS(RCC.bb, "RCC_bb.rds")
    
    message("Pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_DEEPSNV_PAIRWISE_DEEPSNV":',
        paste0('        deepsnv: ', as.character(packageVersion("deepsnv")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pairwise_deepsnv.csv versions.yml
    """
}

workflow BIOC_DEEPSNV_PAIRWISE_DEEPSNV_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ test.bam, control.bam ] ]

    main:
    BIOC_DEEPSNV_PAIRWISE_DEEPSNV(ch_input)

    emit:
    tables   = BIOC_DEEPSNV_PAIRWISE_DEEPSNV.out.tables
    plots    = BIOC_DEEPSNV_PAIRWISE_DEEPSNV.out.plots
    objects  = BIOC_DEEPSNV_PAIRWISE_DEEPSNV.out.objects
    versions = BIOC_DEEPSNV_PAIRWISE_DEEPSNV.out.versions
}
