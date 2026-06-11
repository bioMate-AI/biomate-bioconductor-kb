#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: camutqc — multi_caller_integration
// Integrate somatic mutation calls from multiple variant callers (e.g., MuSE, VarScan2, MuTect2) by filtering each individually and taking their union.
// Input: WES_EA_T_1.MuSE.vep.vcf, WES_EA_T_1_varscan_filter_snp.vep.vcf, WES_EA_T_1_mutect2.vep.vcf, PON_test.txt
// Container: quay.io/biocontainers/bioconductor-camutqc:1.6.0--r45hdfd78af_0
// R packages: CaMutQC
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CAMUTQC_MULTI_CALLER_INTEGRATION {
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
    
    # 1. Convert each caller's VEP-annotated VCF to MAF format using vcfToMAF
    maf_MuSE <- vcfToMAF("WES_EA_T_1.MuSE.vep.vcf") 
    
    # 2. Filter each MAF dataset individually using mutFilterCom
    maf_MuSE_f <- mutFilterCom(maf_MuSE, report=FALSE, TMB=FALSE, 
                               PONfile="PON_test.txt", 
                               PONformat = "txt", progressbar=FALSE)
    
    # Repeat for VarScan2
    maf_VarScan2 <- vcfToMAF("WES_EA_T_1_varscan_filter_snp.vep.vcf")
    maf_VarScan2_f <- mutFilterCom(maf_VarScan2, report=FALSE, TMB=FALSE, 
                                   PONfile="PON_test.txt", 
                                   PONformat="txt", progressbar=FALSE)
    
    # Repeat for MuTect2
    MAFdat <- vcfToMAF("WES_EA_T_1_mutect2.vep.vcf")
    MAFdat_f <- mutFilterCom(MAFdat, report=FALSE, TMB=FALSE, 
                             PONfile="PON_test.txt", 
                             PONformat="txt", progressbar=FALSE)
    
    # 3. Combine the filtered MAF datasets into a list and merge them using the union strategy with processMut
    mafs <- list(maf_MuSE_f, maf_VarScan2_f, MAFdat_f)
    maf_union <- processMut(mafs, processMethod = "union")
    
    # Write named output files for the meaningful results
    write.csv(maf_union, "maf_union_integrated.csv", row.names = FALSE)
    saveRDS(maf_union, "maf_union_integrated.rds")

    writeLines(c(
        '"BIOC_CAMUTQC_MULTI_CALLER_INTEGRATION":',
        paste0('        camutqc: ', as.character(packageVersion("camutqc")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multi_caller_integration.csv versions.yml
    """
}

workflow BIOC_CAMUTQC_MULTI_CALLER_INTEGRATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ WES_EA_T_1.MuSE.vep.vcf, WES_EA_T_1_varscan_filter_snp.vep.vcf, WES_EA_T_1_mutect2.vep.vcf, PON_test.txt ] ]

    main:
    BIOC_CAMUTQC_MULTI_CALLER_INTEGRATION(ch_input)

    emit:
    tables   = BIOC_CAMUTQC_MULTI_CALLER_INTEGRATION.out.tables
    plots    = BIOC_CAMUTQC_MULTI_CALLER_INTEGRATION.out.plots
    objects  = BIOC_CAMUTQC_MULTI_CALLER_INTEGRATION.out.objects
    versions = BIOC_CAMUTQC_MULTI_CALLER_INTEGRATION.out.versions
}
