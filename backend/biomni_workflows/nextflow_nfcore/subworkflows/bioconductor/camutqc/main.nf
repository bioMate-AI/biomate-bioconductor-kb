#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: CaMutQC
// CaMutQC is able to filter false positive mutations generated due to technical issues, as well as to 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/CaMutQC/inst/doc/CaMutQC-manual.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("CaMutQC")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CAMUTQC {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-camutqc"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-camutqc:1.2.0--r44_0' :
        'quay.io/biocontainers/bioconductor-camutqc:1.2.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_camutqc_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_camutqc_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_camutqc_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CaMutQC)
    library(jsonlite)

    # --- VCF Conversion and Parsing [vcfToMAF] ---
    # Key functions: vcfToMAF
    vcf_file <- system.file(
        "extdata", "WES_EA_T_1_mutect2.vep.vcf",
        package = "CaMutQC"
    )
    maf_data <- CaMutQC::vcfToMAF(vcf_file)
    head(maf_data)

    # --- Quality and Strand Bias Filtering [mutFilterQual, mutFilterSB, mutFilterAdj] ---
    # Key functions: mutFilterQual, mutFilterSB, mutFilterAdj
    maf_qual <- CaMutQC::mutFilterQual(
        maf_data, panel = "Customized", VAF = 0.01, VAFratio = 4
    )
    maf_sb <- CaMutQC::mutFilterSB(maf_qual, SBscore = 2)
    maf_adj <- CaMutQC::mutFilterAdj(
        maf_sb, maxIndelLen = 40, minInterval = 15
    )

    # --- Database and Panel-of-Normals Filtering [mutFilterNormalDP, mutFilterPON, mutFilterDB] ---
    # Key functions: mutFilterNormalDP, mutFilterPON, mutFilterDB
    pon_file <- system.file(
        "extdata", "PON_test.txt", package = "CaMutQC"
    )
    maf_pon <- CaMutQC::mutFilterPON(
        maf_data, PONfile = pon_file, PONformat = "txt"
    )
    maf_norm <- CaMutQC::mutFilterNormalDP(
        maf_pon, dbsnpCutoff = 19, nonCutoff = 8
    )
    maf_db <- CaMutQC::mutFilterDB(
        maf_norm, dbSNP = TRUE, dbVAF = 0.01
    )

    # --- Comprehensive Mutation Filtering [mutFilterCom, mutFilterCan] ---
    # Key functions: mutFilterCom, mutFilterCan
    pon_file <- system.file(
        "extdata", "PON_test.txt", package = "CaMutQC"
    )
    maf_com <- CaMutQC::mutFilterCom(
        maf_data, panel = "WES", report = FALSE, TMB = FALSE,
        progressbar = FALSE, PONfile = pon_file, PONformat = "txt"
    )
    maf_can <- CaMutQC::mutFilterCan(
        maf_data, cancerType = "LAML", report = FALSE, TMB = FALSE,
        progressbar = FALSE, PONfile = pon_file, PONformat = "txt"
    )

    # --- Tumor Mutational Burden Calculation [calTMB] ---
    # Key functions: calTMB
    bed_file <- system.file(
        "extdata/bed/panel_hg38", "Pan-cancer-hg38.rds",
        package = "CaMutQC"
    )
    tmb_val <- CaMutQC::calTMB(
        maf_data, assay = "Customized", bedFile = bed_file
    )

    # --- Multi-caller Integration [processMut, vcfToMAF, mutFilterCom] ---
    # Key functions: processMut, vcfToMAF, mutFilterCom
    pon_file <- system.file(
        "extdata", "PON_test.txt", package = "CaMutQC"
    )
    vcf_muse <- system.file(
        "extdata/Multi-caller", "WES_EA_T_1.MuSE.vep.vcf",
        package = "CaMutQC"
    )
    maf_muse <- CaMutQC::vcfToMAF(vcf_muse)
    maf_muse_f <- CaMutQC::mutFilterCom(
        maf_muse, report = FALSE, TMB = FALSE,
        PONfile = pon_file, PONformat = "txt", progressbar = FALSE
    )
    maf_list <- list(maf_muse_f, maf_data)
    maf_union <- CaMutQC::processMut(
        maf_list, processMethod = "union"
    )


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_camutqc_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_camutqc_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_camutqc_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CAMUTQC:", paste0("    camutqc: ", packageVersion("CaMutQC"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_camutqc_results.csv
    touch ${prefix}_camutqc_output.rds
    echo "BIOC_CAMUTQC:" > versions.yml
    echo "    camutqc: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CAMUTQC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CAMUTQC(ch_input)

    emit:
    results  = BIOC_CAMUTQC.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CAMUTQC.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CAMUTQC.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CAMUTQC.out.versions  // channel: path(versions.yml)
}
