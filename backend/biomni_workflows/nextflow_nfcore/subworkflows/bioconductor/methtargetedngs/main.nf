#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: methtargetedngs — comparative_methylation_analysis
// Align NGS reads from two conditions to a reference sequence and perform comparative methylation analysis.
// Input: Healthy.fasta, Tumor.fasta, Reference.fasta
// Container: quay.io/biocontainers/bioconductor-methtargetedngs:1.42.0--r45hdfd78af_0
// R packages: MethTargetedNGS
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_METHTARGETEDNGS_COMPARATIVE_METHYLATION_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-methtargetedngs:1.42.0--r45hdfd78af_0"

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
    .bm_deps <- c("MethTargetedNGS")
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
    
    # Load the required Bioconductor library
    library(MethTargetedNGS)
    
    # Define input file paths (must exist in the working directory)
    healthy <- "Healthy.fasta"
    tumor <- "Tumor.fasta"
    reference <- "Reference.fasta"
    
    # Validate existence of user input files
    if (!file.exists(healthy)) {
      stop("Error: 'Healthy.fasta' not found in the working directory.")
    }
    if (!file.exists(tumor)) {
      stop("Error: 'Tumor.fasta' not found in the working directory.")
    }
    if (!file.exists(reference)) {
      stop("Error: 'Reference.fasta' not found in the working directory.")
    }
    
    # --- Align reads to reference using methAlign ---
    message("Aligning healthy reads to reference...")
    hAlign <- methAlign(healthy, reference)
    
    message("Aligning tumor reads to reference...")
    tAlign <- methAlign(tumor, reference)
    
    # Save alignment matrices as RDS and CSV
    saveRDS(hAlign, "healthy_alignment.rds")
    saveRDS(tAlign, "tumor_alignment.rds")
    write.csv(as.data.frame(hAlign), "healthy_alignment.csv", row.names = TRUE)
    write.csv(as.data.frame(tAlign), "tumor_alignment.csv", row.names = TRUE)
    
    # --- Generate methylation heatmap using methHeatmap ---
    message("Generating methylation heatmap...")
    pdf("healthy_heatmap.pdf", width = 10, height = 8)
    hHeatmap <- methHeatmap(hAlign, plot = TRUE)
    dev.off()
    saveRDS(hHeatmap, "healthy_heatmap_data.rds")
    
    # --- Calculate methylation average using methAvg ---
    message("Calculating methylation average...")
    hAvg <- methAvg(hAlign, plot = FALSE)
    write.csv(data.frame(CpG_Site = seq_along(hAvg), Average_Methylation = hAvg), 
              "healthy_average.csv", row.names = FALSE)
    
    # --- Calculate methylation entropy using methEntropy ---
    message("Calculating methylation entropy...")
    hEnt <- methEntropy(hAlign)
    write.csv(data.frame(Window = seq_along(hEnt), Entropy = hEnt), 
              "healthy_entropy.csv", row.names = FALSE)
    
    # --- Identify significant CpG sites using fishertest_cpg ---
    message("Identifying significant CpG sites...")
    SigCpGsites <- fishertest_cpg(hAlign, tAlign, plot = FALSE)
    write.csv(data.frame(CpG_Site = seq_along(SigCpGsites), Fisher_FDR = SigCpGsites), 
              "significant_cpg_sites.csv", row.names = FALSE)
    
    # --- Calculate log odd ratios using odd_ratio ---
    message("Calculating log odd ratios...")
    odSamps <- odd_ratio(hAlign, tAlign, plot = FALSE)
    write.csv(data.frame(CpG_Site = seq_along(odSamps), Log_Odd_Ratio = odSamps), 
              "odd_ratios.csv", row.names = FALSE)
    
    # --- Run complete comparative pipeline using compare_samples ---
    message("Running complete comparative pipeline and saving plots...")
    pdf("comparative_analysis_plots.pdf", width = 12, height = 10)
    compare_samples(hAlign, tAlign)
    dev.off()
    
    message("Workflow completed successfully. All outputs saved to the working directory.")

    writeLines(c(
        '"BIOC_METHTARGETEDNGS_COMPARATIVE_METHYLATION_ANALYSIS":',
        paste0('        methtargetedngs: ', as.character(packageVersion("methtargetedngs")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_comparative_methylation_analysis.csv versions.yml
    """
}

workflow BIOC_METHTARGETEDNGS_COMPARATIVE_METHYLATION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Healthy.fasta, Tumor.fasta, Reference.fasta ] ]

    main:
    BIOC_METHTARGETEDNGS_COMPARATIVE_METHYLATION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_METHTARGETEDNGS_COMPARATIVE_METHYLATION_ANALYSIS.out.tables
    plots    = BIOC_METHTARGETEDNGS_COMPARATIVE_METHYLATION_ANALYSIS.out.plots
    objects  = BIOC_METHTARGETEDNGS_COMPARATIVE_METHYLATION_ANALYSIS.out.objects
    versions = BIOC_METHTARGETEDNGS_COMPARATIVE_METHYLATION_ANALYSIS.out.versions
}
