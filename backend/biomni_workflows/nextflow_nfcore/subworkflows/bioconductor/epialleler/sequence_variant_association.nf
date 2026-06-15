#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: epialleler — sequence_variant_association
// Test the association between single nucleotide variants (SNVs) and epiallelic status.
// Input: amplicon010meth.bam, amplicon.bed, amplicon.vcf.gz
// Container: quay.io/biocontainers/bioconductor-epialleler:1.18.0--r45ha27e39d_0
// R packages: data.table, epialleleR
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_EPIALLELER_SEQUENCE_VARIANT_ASSOCIATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-epialleler:1.18.0--r45ha27e39d_0"

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
    .bm_deps <- c("data.table", "epialleleR")
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
    
    # Load required libraries
    library(epialleleR)
    library(data.table)
    
    # Define input file paths from the working directory
    bam_input <- "amplicon010meth.bam"
    bed_input <- "amplicon.bed"
    vcf_input <- "amplicon.vcf.gz"
    
    # Verify that the required input files exist
    for (file in c(bam_input, bed_input, vcf_input)) {
      if (!file.exists(file)) {
        stop(paste("Required input file missing in the working directory:", file))
      }
    }
    
    # --- Generate VCF report using generateVcfReport with ---
    message("Generating VCF report...")
    vcf.report <- generateVcfReport(
      bam=bam_input,
      bed=bed_input,
      vcf=vcf_input,
      min.mapq=30,
      min.baseq=20,
      vcf.style="NCBI"
    )
    
    # --- Sort the report by Fisher's exact test p-values (FEp- and ---
    message("Sorting reports by Fisher's exact test p-values...")
    sorted_fep_minus <- vcf.report[order(`FEp-`, na.last=TRUE)]
    sorted_fep_plus  <- vcf.report[order(`FEp+`, na.last=TRUE)]
    
    # Print the top records to console as documented
    message("Top records sorted by FEp-:")
    print(head(sorted_fep_minus))
    
    message("Top records sorted by FEp+:")
    print(head(sorted_fep_plus))
    
    # --- Write output files for the meaningful results ---
    message("Writing output files...")
    # Save the full report as an RDS object
    saveRDS(vcf.report, file="vcf_report.rds")
    
    # Save the full and sorted reports as CSV tables
    data.table::fwrite(vcf.report, file="vcf_report_full.csv")
    data.table::fwrite(sorted_fep_minus, file="vcf_report_sorted_FEp_minus.csv")
    data.table::fwrite(sorted_fep_plus, file="vcf_report_sorted_FEp_plus.csv")
    
    message("Pipeline completed successfully. Outputs saved: vcf_report.rds, vcf_report_full.csv, vcf_report_sorted_FEp_minus.csv, vcf_report_sorted_FEp_plus.csv")

    writeLines(c(
        '"BIOC_EPIALLELER_SEQUENCE_VARIANT_ASSOCIATION":',
        paste0('        epialleler: ', as.character(packageVersion("epialleler")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sequence_variant_association.csv versions.yml
    """
}

workflow BIOC_EPIALLELER_SEQUENCE_VARIANT_ASSOCIATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ amplicon010meth.bam, amplicon.bed, amplicon.vcf.gz ] ]

    main:
    BIOC_EPIALLELER_SEQUENCE_VARIANT_ASSOCIATION(ch_input)

    emit:
    tables   = BIOC_EPIALLELER_SEQUENCE_VARIANT_ASSOCIATION.out.tables
    plots    = BIOC_EPIALLELER_SEQUENCE_VARIANT_ASSOCIATION.out.plots
    objects  = BIOC_EPIALLELER_SEQUENCE_VARIANT_ASSOCIATION.out.objects
    versions = BIOC_EPIALLELER_SEQUENCE_VARIANT_ASSOCIATION.out.versions
}
