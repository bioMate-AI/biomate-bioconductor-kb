#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: camutqc — cancer_or_reference_specific_filtering
// Filter somatic mutations using cancer-type-specific or published reference-specific filtering strategies.
// Input: WES_EA_T_1_mutect2.vep.vcf, PON_test.txt
// Container: quay.io/biocontainers/bioconductor-camutqc:1.6.0--r45hdfd78af_0
// R packages: CaMutQC
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CAMUTQC_CANCER_OR_REFERENCE_SPECIFIC_FILTERING {
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
    
    # Define input file paths from the working directory
    vcf_input <- "WES_EA_T_1_mutect2.vep.vcf"
    pon_input <- "PON_test.txt"
    
    # Verify that the required input files exist in the working directory
    if (!file.exists(vcf_input)) {
      stop(paste("Required input VCF file not found in the working directory:", vcf_input))
    }
    if (!file.exists(pon_input)) {
      stop(paste("Required Panel of Normals (PON) file not found in the working directory:", pon_input))
    }
    
    # Stage 1: Convert VEP-annotated VCF to MAF format
    message("Converting VEP-annotated VCF to MAF format...")
    MAFdat <- vcfToMAF(vcf_input)
    
    # Save the intermediate converted MAF data
    write.csv(MAFdat, "MAFdat_converted.csv", row.names = FALSE)
    saveRDS(MAFdat, "MAFdat_converted.rds")
    
    # Stage 2: Apply cancer-type-specific filtering (e.g., LAML)
    message("Applying cancer-type-specific filtering (LAML)...")
    MAFCan <- mutFilterCan(MAFdat, cancerType='LAML', report=FALSE, TMB=FALSE, 
                           progressbar=FALSE, 
                           PONfile=pon_input, PONformat="txt")
    
    # Save the cancer-type-specific filtered MAF data
    write.csv(MAFCan, "MAF_cancer_specific_LAML_filtered.csv", row.names = FALSE)
    saveRDS(MAFCan, "MAF_cancer_specific_LAML_filtered.rds")
    
    # Stage 3: Apply reference-study-specific filtering (e.g., Zhu et al. 2020 KIRP)
    message("Applying reference-study-specific filtering (Zhu_et_al-Nat_Commun-2020-KIRP)...")
    MAFRef <- mutFilterRef(MAFdat, reference="Zhu_et_al-Nat_Commun-2020-KIRP", 
                           report=FALSE, TMB=FALSE, progressbar=FALSE,
                           PONfile=pon_input, PONformat="txt")
    
    # Save the reference-study-specific filtered MAF data
    write.csv(MAFRef, "MAF_reference_specific_KIRP_filtered.csv", row.names = FALSE)
    saveRDS(MAFRef, "MAF_reference_specific_KIRP_filtered.rds")
    
    # Print summary of results
    message("Pipeline completed successfully!")
    message(paste("Total mutations before filtering:", nrow(MAFdat)))
    message(paste("Mutations passing LAML cancer-specific filtering:", sum(MAFCan\$CaTag == "0")))
    message(paste("Mutations passing Zhu et al. 2020 KIRP reference filtering:", sum(MAFRef\$CaTag == "0")))

    cat <<-END_VERSIONS > versions.yml
    "BIOC_CAMUTQC_CANCER_OR_REFERENCE_SPECIFIC_FILTERING":
        camutqc: \$(Rscript -e 'cat(as.character(packageVersion("camutqc")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cancer_or_reference_specific_filtering.csv versions.yml
    """
}

workflow BIOC_CAMUTQC_CANCER_OR_REFERENCE_SPECIFIC_FILTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ WES_EA_T_1_mutect2.vep.vcf, PON_test.txt ] ]

    main:
    BIOC_CAMUTQC_CANCER_OR_REFERENCE_SPECIFIC_FILTERING(ch_input)

    emit:
    tables   = BIOC_CAMUTQC_CANCER_OR_REFERENCE_SPECIFIC_FILTERING.out.tables
    plots    = BIOC_CAMUTQC_CANCER_OR_REFERENCE_SPECIFIC_FILTERING.out.plots
    objects  = BIOC_CAMUTQC_CANCER_OR_REFERENCE_SPECIFIC_FILTERING.out.objects
    versions = BIOC_CAMUTQC_CANCER_OR_REFERENCE_SPECIFIC_FILTERING.out.versions
}
