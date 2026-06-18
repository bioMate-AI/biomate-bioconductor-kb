#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: BaalChIP — asb_with_precomputed_raf
// Identify allele-specific binding events using pre-computed relative allele frequency (RAF) scores from heterozygous variant files.
// Input: exampleChIP1.tsv, MCF7_hetSNP.txt, GM12891_hetSNP.txt, bamFiles/, bedFiles/
// Container: quay.io/biocontainers/bioconductor-baalchip:1.36.0--r45hdfd78af_0
// R packages: GenomicRanges, BaalChIP
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: plot (ggplot/base)

nextflow.enable.dsl = 2

process BIOC_BAALCHIP_ASB_WITH_PRECOMPUTED_RAF {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-baalchip:1.36.0--r45hdfd78af_0"

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
    .bm_deps <- c("GenomicRanges", "BaalChIP")
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
    library(BaalChIP)
    library(GenomicRanges)
    
    # -----------------------------------------------------------------------------
    # 1. Validate User Input Files
    # -----------------------------------------------------------------------------
    required_files <- c("exampleChIP1.tsv", "MCF7_hetSNP.txt", "GM12891_hetSNP.txt")
    for (f in required_files) {
      if (!file.exists(f)) {
        stop(paste("Required input file missing from working directory:", f))
      }
    }
    
    if (!dir.exists("bamFiles")) {
      stop("Required directory 'bamFiles/' is missing from working directory.")
    }
    
    if (!dir.exists("bedFiles")) {
      stop("Required directory 'bedFiles/' is missing from working directory.")
    }
    
    # Locate pre-computed simulation output directory
    # First check the working directory, then fall back to the installed package directory
    preComputed_output <- "simuloutput"
    if (!dir.exists(preComputed_output)) {
      package_path <- find.package("BaalChIP", quiet = TRUE)
      if (length(package_path) > 0) {
        preComputed_output <- file.path(package_path, "test", "simuloutput")
      }
    }
    
    if (!dir.exists(preComputed_output)) {
      stop("Could not locate the pre-computed simulation output directory ('simuloutput').")
    }
    
    # -----------------------------------------------------------------------------
    # 2. Execute BaalChIP Pipeline
    # -----------------------------------------------------------------------------
    
    # Define inputs
    samplesheet <- "exampleChIP1.tsv"
    hets <- c("MCF7" = "MCF7_hetSNP.txt", "GM12891" = "GM12891_hetSNP.txt")
    
    # --- Construct BaalChIP object ---
    message("Constructing BaalChIP object...")
    res <- BaalChIP(samplesheet=samplesheet, hets=hets)
    
    # --- Compute allele counts ---
    message("Computing allele counts...")
    res <- alleleCounts(res, min_base_quality=10, min_mapq=15, verbose=FALSE)
    
    # --- Filter problematic regions ---
    message("Filtering problematic regions (QCfilter)...")
    res <- QCfilter(res, 
                    RegionsToFilter=list("blacklist"=blacklist_hg19, "highcoverage"=pickrell2011cov1_hg19), 
                    RegionsToKeep=list("UniqueMappability"=UniqueMappability50bp_hg19), 
                    verbose=FALSE)
    
    # --- Filter intrinsic bias ---
    message("Filtering intrinsic bias...")
    res <- filterIntbias(res, 
                         simul_output=preComputed_output, 
                         tmpfile_prefix="c67c6ec6c433", 
                         skipScriptRun=TRUE, 
                         verbose=FALSE)
    
    # --- Merge replicates ---
    message("Merging replicates per group...")
    res <- mergePerGroup(res)
    
    # --- Filter out homozygous SNPs ---
    message("Filtering out homozygous SNPs...")
    res <- filter1allele(res)
    
    # --- Run Bayesian ASB detection ---
    message("Running Bayesian ASB detection...")
    res <- getASB(res, 
                  Iter=5000, 
                  conf_level=0.95, 
                  cores=4, 
                  RMcorrection=TRUE, 
                  RAFcorrection=TRUE)
    
    # --- Generate final report ---
    message("Generating final report...")
    result <- BaalChIP.report(res)
    
    # -----------------------------------------------------------------------------
    # 3. Save Outputs and Generate Plots
    # -----------------------------------------------------------------------------
    
    # Save the final report as CSV files
    message("Saving report tables...")
    for (group in names(result)) {
      output_csv <- paste0("BaalChIP_report_", group, ".csv")
      write.csv(result[[group]], file = output_csv, row.names = FALSE)
      message(paste("Saved:", output_csv))
    }
    
    # Save the complete BaalChIP object
    output_rds <- "BaalChIP_results.rds"
    saveRDS(res, file = output_rds)
    message(paste("Saved BaalChIP object to:", output_rds))
    
    # Generate diagnostic plots
    output_pdf <- "BaalChIP_plots.pdf"
    message(paste("Generating diagnostic plots in:", output_pdf))
    pdf(output_pdf, width = 10, height = 8)
    
    # Plot QC filtering statistics if available
    tryCatch({
      plotQC(res, what="barplot_per_group")
      plotQC(res, what="boxplot_per_filter")
      plotQC(res, what="overall_pie")
    }, error = function(e) {
      warning("Could not generate QC plots: ", e\$message)
    })
    
    # Plot allelic ratio adjustments
    tryCatch({
      adjustmentBaalPlot(res)
    }, error = function(e) {
      warning("Could not generate adjustment plot: ", e\$message)
    })
    
    dev.off()
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_BAALCHIP_ASB_WITH_PRECOMPUTED_RAF":',
        paste0('        BaalChIP: ', as.character(packageVersion("BaalChIP")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_asb_with_precomputed_raf.csv versions.yml
    """
}

workflow BIOC_BAALCHIP_ASB_WITH_PRECOMPUTED_RAF_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ exampleChIP1.tsv, MCF7_hetSNP.txt, GM12891_hetSNP.txt, bamFiles/, bedFiles/ ] ]

    main:
    BIOC_BAALCHIP_ASB_WITH_PRECOMPUTED_RAF(ch_input)

    emit:
    tables   = BIOC_BAALCHIP_ASB_WITH_PRECOMPUTED_RAF.out.tables
    plots    = BIOC_BAALCHIP_ASB_WITH_PRECOMPUTED_RAF.out.plots
    objects  = BIOC_BAALCHIP_ASB_WITH_PRECOMPUTED_RAF.out.objects
    versions = BIOC_BAALCHIP_ASB_WITH_PRECOMPUTED_RAF.out.versions
}
