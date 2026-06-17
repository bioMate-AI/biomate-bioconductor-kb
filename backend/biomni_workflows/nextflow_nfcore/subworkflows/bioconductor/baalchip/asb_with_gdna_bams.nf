#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: BaalChIP — asb_with_gdna_bams
// Identify allele-specific binding events using genomic DNA (gDNA) BAM files to calculate relative allele frequency (RAF) scores.
// Input: exampleChIP2.tsv, TaT1_hetSNP.txt, AMOVC_hetSNP.txt, bamFiles/, bedFiles/
// Container: quay.io/biocontainers/bioconductor-baalchip:1.36.0--r45hdfd78af_0
// R packages: BaalChIP
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BAALCHIP_ASB_WITH_GDNA_BAMS {
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
    .bm_deps <- c("BaalChIP")
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
    library(BaalChIP)
    
    # Define working directory as current directory
    wd <- "."
    
    # Define paths to user input files
    samplesheet <- file.path(wd, "exampleChIP2.tsv")
    hets <- c("TaT1" = file.path(wd, "TaT1_hetSNP.txt"), "AMOVC" = file.path(wd, "AMOVC_hetSNP.txt"))
    
    # Define gDNA BAM files list (reproduced exactly from documented code)
    gDNA <- list(
      "TaT1" = c(file.path(wd, "bamFiles/TaT1_1_gDNA.test.bam"), file.path(wd, "bamFiles/TaT1_2_gDNA.test.bam")),
      "AMOVC" = c(file.path(wd, "bamFiles/AMOVC_1_gDNA.test.bam"), file.path(wd, "bamFiles/AMOVC_2_gDNA.test.bam"))
    )
    
    # Construct BaalChIP object with CorrectWithgDNA
    res2 <- BaalChIP(samplesheet=samplesheet, hets=hets, CorrectWithgDNA=gDNA)
    
    # Run the complete pipeline
    res2 <- BaalChIP.run(res2, cores=4, verbose=TRUE)
    
    # Generate final report
    result <- BaalChIP.report(res2)
    
    # Save the final BaalChIP object
    saveRDS(res2, file = "BaalChIP_results.rds")
    
    # Export reports to CSV files
    for (group in names(result)) {
      write.csv(result[[group]], file = paste0(group, "_ASB_report.csv"), row.names = FALSE)
    }
    
    # Generate and save QC plots
    pdf("BaalChIP_QC_plots.pdf")
    tryCatch({
      plotQC(res2, what="barplot_per_group")
    }, error = function(e) {
      message("Could not plot barplot_per_group: ", e\$message)
    })
    tryCatch({
      plotQC(res2, what="boxplot_per_filter")
    }, error = function(e) {
      message("Could not plot boxplot_per_filter: ", e\$message)
    })
    tryCatch({
      plotQC(res2, what="overall_pie")
    }, error = function(e) {
      message("Could not plot overall_pie: ", e\$message)
    })
    dev.off()
    
    # Generate and save adjustment plots
    pdf("BaalChIP_adjustment_plots.pdf")
    tryCatch({
      adjustmentBaalPlot(res2)
    }, error = function(e) {
      message("Could not plot adjustmentBaalPlot: ", e\$message)
    })
    dev.off()

    writeLines(c(
        '"BIOC_BAALCHIP_ASB_WITH_GDNA_BAMS":',
        paste0('        BaalChIP: ', as.character(packageVersion("BaalChIP")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_asb_with_gdna_bams.csv versions.yml
    """
}

workflow BIOC_BAALCHIP_ASB_WITH_GDNA_BAMS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ exampleChIP2.tsv, TaT1_hetSNP.txt, AMOVC_hetSNP.txt, bamFiles/, bedFiles/ ] ]

    main:
    BIOC_BAALCHIP_ASB_WITH_GDNA_BAMS(ch_input)

    emit:
    tables   = BIOC_BAALCHIP_ASB_WITH_GDNA_BAMS.out.tables
    plots    = BIOC_BAALCHIP_ASB_WITH_GDNA_BAMS.out.plots
    objects  = BIOC_BAALCHIP_ASB_WITH_GDNA_BAMS.out.objects
    versions = BIOC_BAALCHIP_ASB_WITH_GDNA_BAMS.out.versions
}
