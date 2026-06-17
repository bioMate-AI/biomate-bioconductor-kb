#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: epialleleR — snv_epiallele_association
// Test the association between single nucleotide variants (SNVs) and epiallelic methylation status using Fisher's Exact Test.
// Input: amplicon010meth.bam, amplicon.bed, amplicon.vcf.gz
// Container: quay.io/biocontainers/bioconductor-epialleler:1.18.0--r45ha27e39d_0
// R packages: GenomicRanges, epialleleR
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, epialleleR
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Generate a VCF report calculating SNV frequencies within epialleles and testing association
//  * 2. [Visualization & Output] Sort the report by Fisher's exact test p-values
//  * 3. [Visualization & Output] Extract and plot methylation patterns highlighting the SNP position

nextflow.enable.dsl = 2

process BIOC_EPIALLELER_SNV_EPIALLELE_ASSOCIATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

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
    .bm_deps <- c("GenomicRanges", "epialleleR")
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
    library(epialleleR)
    library(GenomicRanges)
    
    # Define input files from the working directory
    bam_file <- "amplicon010meth.bam"
    bed_file <- "amplicon.bed"
    vcf_file <- "amplicon.vcf.gz"
    
    # 1. Generate a VCF report calculating SNV frequencies within epialleles and testing association
    vcf.report <- generateVcfReport(
      bam=bam_file,
      bed=bed_file,
      vcf=vcf_file,
      min.mapq=30, min.baseq=20,
      vcf.style="NCBI"
    )
    
    # Display the head of the generated report
    print("VCF Report Head:")
    print(head(vcf.report))
    
    # 2. Sort the report by Fisher's exact test p-values (FEp- and FEp+)
    vcf_report_sorted_fep_minus <- vcf.report[order(`FEp-`, na.last=TRUE)]
    vcf_report_sorted_fep_plus  <- vcf.report[order(`FEp+`, na.last=TRUE)]
    
    print("VCF Report Sorted by FEp-:")
    print(head(vcf_report_sorted_fep_minus))
    
    print("VCF Report Sorted by FEp+:")
    print(head(vcf_report_sorted_fep_plus))
    
    # Save the reports to CSV files
    write.csv(vcf.report, "vcf_report.csv", row.names=FALSE)
    write.csv(vcf_report_sorted_fep_minus, "vcf_report_sorted_FEp_minus.csv", row.names=FALSE)
    write.csv(vcf_report_sorted_fep_plus, "vcf_report_sorted_FEp_plus.csv", row.names=FALSE)
    
    # 3. Extract and plot methylation patterns highlighting the SNP position
    # We adapt the coordinates to target a highly covered SNP in the amplicon dataset (e.g., rs535977743 at chr17:43125016)
    brip1.patterns <- extractPatterns(
      bam=bam_file,
      bed=as("chr17:43125015-43125017", "GRanges"),
      highlight.positions=43125016,
      verbose=FALSE
    )
    
    # Save the extracted patterns object
    saveRDS(brip1.patterns, "brip1_patterns.rds")
    
    # Plot the patterns and save to a PDF file
    pdf("patterns_plot.pdf", width=10, height=6)
    plotPatterns(brip1.patterns)
    dev.off()

    writeLines(c(
        '"BIOC_EPIALLELER_SNV_EPIALLELE_ASSOCIATION":',
        paste0('    epialleleR: ', as.character(packageVersion('epialleleR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_snv_epiallele_association.csv versions.yml
    """
}

workflow BIOC_EPIALLELER_SNV_EPIALLELE_ASSOCIATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ amplicon010meth.bam, amplicon.bed, amplicon.vcf.gz ] ]

    main:
    BIOC_EPIALLELER_SNV_EPIALLELE_ASSOCIATION(ch_input)

    emit:
    tables   = BIOC_EPIALLELER_SNV_EPIALLELE_ASSOCIATION.out.tables
    plots    = BIOC_EPIALLELER_SNV_EPIALLELE_ASSOCIATION.out.plots
    objects  = BIOC_EPIALLELER_SNV_EPIALLELE_ASSOCIATION.out.objects
    versions = BIOC_EPIALLELER_SNV_EPIALLELE_ASSOCIATION.out.versions
}
