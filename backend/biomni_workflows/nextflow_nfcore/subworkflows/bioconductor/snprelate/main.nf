#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: snprelate — gds_format_conversion
// Convert PLINK binary files or VCF files into the GDS format required for downstream SNPRelate analyses.
// Input: bed.fn, fam.fn, bim.fn, vcf.fn
// Container: quay.io/biocontainers/bioconductor-snprelate:1.44.0--r45ha27e39d_0
// R packages: gdsfmt, MASS, SNPRelate
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SNPRELATE_GDS_FORMAT_CONVERSION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-snprelate:1.44.0--r45ha27e39d_0"

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
    .bm_deps <- c("gdsfmt", "MASS", "SNPRelate")
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
    library(gdsfmt)
    library(SNPRelate)
    
    # Define input file paths in the working directory
    bed.fn <- "bed.fn"
    fam.fn <- "fam.fn"
    bim.fn <- "bim.fn"
    vcf.fn <- "vcf.fn"
    
    # Verify input files exist before proceeding
    missing_files <- c()
    if (!file.exists(bed.fn)) missing_files <- c(missing_files, bed.fn)
    if (!file.exists(fam.fn)) missing_files <- c(missing_files, fam.fn)
    if (!file.exists(bim.fn)) missing_files <- c(missing_files, bim.fn)
    if (!file.exists(vcf.fn)) missing_files <- c(missing_files, vcf.fn)
    
    if (length(missing_files) > 0) {
      stop(paste("Missing required input files in the working directory:", 
                 paste(missing_files, collapse = ", ")))
    }
    
    # Clean up any pre-existing test.gds to avoid conflicts
    if (file.exists("test.gds")) {
      file.remove("test.gds")
    }
    
    # Convert PLINK
    snpgdsBED2GDS(bed.fn, fam.fn, bim.fn, "test.gds")
    
    # Summary
    snpgdsSummary("test.gds")
    
    # Save PLINK GDS summary to RDS
    plink_summary <- snpgdsSummary("test.gds")
    saveRDS(plink_summary, "plink_gds_summary.rds")
    
    # Clean up test.gds before VCF conversion to prevent overwrite issues
    if (file.exists("test.gds")) {
      file.remove("test.gds")
    }
    
    # Convert VCF
    snpgdsVCF2GDS(vcf.fn, "test.gds", method="biallelic.only")
    
    # Summary
    snpgdsSummary("test.gds")
    
    # Save VCF GDS summary to RDS
    vcf_summary <- snpgdsSummary("test.gds")
    saveRDS(vcf_summary, "vcf_gds_summary.rds")

    writeLines(c(
        '"BIOC_SNPRELATE_GDS_FORMAT_CONVERSION":',
        paste0('        snprelate: ', as.character(packageVersion("snprelate")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gds_format_conversion.csv versions.yml
    """
}

workflow BIOC_SNPRELATE_GDS_FORMAT_CONVERSION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ bed.fn, fam.fn, bim.fn, vcf.fn ] ]

    main:
    BIOC_SNPRELATE_GDS_FORMAT_CONVERSION(ch_input)

    emit:
    tables   = BIOC_SNPRELATE_GDS_FORMAT_CONVERSION.out.tables
    plots    = BIOC_SNPRELATE_GDS_FORMAT_CONVERSION.out.plots
    objects  = BIOC_SNPRELATE_GDS_FORMAT_CONVERSION.out.objects
    versions = BIOC_SNPRELATE_GDS_FORMAT_CONVERSION.out.versions
}
