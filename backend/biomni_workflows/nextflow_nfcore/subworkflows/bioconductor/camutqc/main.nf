#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: camutqc — single_vcf_filtering_and_tmb
// Convert a single VEP-annotated VCF to MAF, apply comprehensive quality control and candidate selection filters, and calculate Tumor Mutational Burden (TMB).
// Input: WES_EA_T_1_mutect2.vep.vcf, PON_test.txt, Pan-cancer-hg38.rds
// Container: quay.io/biocontainers/bioconductor-camutqc:1.6.0--r45hdfd78af_0
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
    .bm_deps <- c("camutqc")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
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

    cat <<-END_VERSIONS > versions.yml
    "BIOC_CAMUTQC_SINGLE_VCF_FILTERING_AND_TMB":
        camutqc: \$(Rscript -e 'cat(as.character(packageVersion("camutqc")))')
    END_VERSIONS
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
