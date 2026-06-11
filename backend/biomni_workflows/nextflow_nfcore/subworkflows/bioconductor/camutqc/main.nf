#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: camutqc — single_vcf_filtering_and_tmb
// Convert a single VEP-annotated VCF to MAF, apply comprehensive quality control and candidate selection filters, and calculate Tumor Mutational Burden (TMB).
// Input: WES_EA_T_1_mutect2.vep.vcf, PON_test.txt, Pan-cancer-hg38.rds
// Container: quay.io/biocontainers/bioconductor-camutqc:1.6.0--r45hdfd78af_0
// R packages: CaMutQC
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CAMUTQC_SINGLE_VCF_FILTERING_AND_TMB {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-camutqc:1.6.0--r45hdfd78af_0"

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
    .bm_deps <- c("CaMutQC")
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
    library(CaMutQC)
    
    # Define input file paths (expected in the working directory)
    vcf_file <- "WES_EA_T_1_mutect2.vep.vcf"
    bed_file <- "Pan-cancer-hg38.rds"
    pon_file <- "PON_test.txt"
    
    # Verify input files exist before running the pipeline
    if (!file.exists(vcf_file)) {
      stop(paste("Required input file not found in working directory:", vcf_file))
    }
    if (!file.exists(bed_file)) {
      stop(paste("Required input file not found in working directory:", bed_file))
    }
    if (!file.exists(pon_file)) {
      stop(paste("Required input file not found in working directory:", pon_file))
    }
    
    # 1. Convert VEP-annotated VCF to MAF format
    message("Converting VEP-annotated VCF to MAF...")
    MAFdat <- vcfToMAF(vcf_file)
    
    # Save intermediate MAF data
    write.csv(MAFdat, "MAFdat_converted.csv", row.names = FALSE)
    saveRDS(MAFdat, "MAFdat_converted.rds")
    
    # 2. Apply combined technical and candidate selection filters, and calculate TMB
    message("Applying combined filters and calculating TMB...")
    MAFCom_tmb <- mutFilterCom(
      MAFdat, 
      panel = "WES", 
      assay = "Customized", 
      report = FALSE, 
      TMB = TRUE, 
      bedFile = bed_file, 
      PONfile = pon_file, 
      PONformat = "txt", 
      progressbar = FALSE, 
      verbose = FALSE
    )
    
    # Save final filtered MAF data with TMB annotations
    write.csv(MAFCom_tmb, "MAFCom_filtered_tmb.csv", row.names = FALSE)
    saveRDS(MAFCom_tmb, "MAFCom_filtered_tmb.rds")
    
    message("Pipeline completed successfully.")
    message("Outputs saved:")
    message("  - MAFdat_converted.csv / .rds (Unfiltered MAF)")
    message("  - MAFCom_filtered_tmb.csv / .rds (Filtered MAF with TMB calculation)")

    writeLines(c(
        '"BIOC_CAMUTQC_SINGLE_VCF_FILTERING_AND_TMB":',
        paste0('        camutqc: ', as.character(packageVersion("camutqc")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_vcf_filtering_and_tmb.csv versions.yml
    """
}

workflow BIOC_CAMUTQC_SINGLE_VCF_FILTERING_AND_TMB_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ WES_EA_T_1_mutect2.vep.vcf, PON_test.txt, Pan-cancer-hg38.rds ] ]

    main:
    BIOC_CAMUTQC_SINGLE_VCF_FILTERING_AND_TMB(ch_input)

    emit:
    tables   = BIOC_CAMUTQC_SINGLE_VCF_FILTERING_AND_TMB.out.tables
    plots    = BIOC_CAMUTQC_SINGLE_VCF_FILTERING_AND_TMB.out.plots
    objects  = BIOC_CAMUTQC_SINGLE_VCF_FILTERING_AND_TMB.out.objects
    versions = BIOC_CAMUTQC_SINGLE_VCF_FILTERING_AND_TMB.out.versions
}
