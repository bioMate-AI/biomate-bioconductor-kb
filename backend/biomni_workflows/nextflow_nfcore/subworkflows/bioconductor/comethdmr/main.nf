#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: coMethDMR
// coMethDMR identifies genomic regions associated with continuous phenotypes by optimally leverages co
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/coMethDMR/inst/doc/vin1_Introduction_to_coMethDMR_geneBasedPipeline.R
// Upstream  : BiocParallel, GenoGAM, corrplot
// Downstream: none
//
// Install: BiocManager::install("coMethDMR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_COMETHDMR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-comethdmr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-comethdmr:1.10.0--r44_0' :
        'quay.io/biocontainers/bioconductor-comethdmr:1.10.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_comethdmr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_comethdmr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_comethdmr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(coMethDMR)
    library(AnnotateResults)
    library(CoMethAllRegions)
    library(CpGsInfoOneRegion)
    library(GetResiduals)
    library(jsonlite)

    # --- Adjusting for Covariates [GetResiduals] ---
    # Key functions: GetResiduals
    data(betasChr22_df)
    data(pheno_df)
    resid_mat <- GetResiduals(
        dnam = betasChr22_df,
        betaToM = TRUE,
        pheno_df = pheno_df,
        covariates_char = c("age.brain", "sex", "slide")
    )

    # --- Defining Genomic Regions [CloseBySingleRegion, OrderCpGsByLocation, NameRegion] ---
    # Key functions: CloseBySingleRegion, OrderCpGsByLocation, NameRegion
    ARFGAP3_CpGs_char <- c(
        "cg00079563", "cg01029450", "cg02351223", "cg04527868", "cg09861871",
        "cg26529516", "cg00539564", "cg05288033", "cg09367092", "cg10648908"
    )
    gene3_200 <- CloseBySingleRegion(
        CpGs_char = ARFGAP3_CpGs_char,
        arrayType = "450k",
        maxGap = 200,
        minCpGs = 3
    )
    CpGsOrdered_ls <- lapply(
        gene3_200,
        OrderCpGsByLocation,
        arrayType = "450k",
        output = "dataframe"
    )
    names(gene3_200) <- lapply(CpGsOrdered_ls, NameRegion)

    # --- Identifying Co-methylated Regions [CoMethAllRegions] ---
    # Key functions: CoMethAllRegions
    data(betasChr22_df)
    CpGisland_ls <- readRDS(
        system.file(
            "extdata", "CpGislandsChr22_ex.rds",
            package = "coMethDMR", mustWork = TRUE
        )
    )
    coMeth_ls <- CoMethAllRegions(
        dnam = betasChr22_df,
        betaToM = TRUE,
        method = "pearson",
        CpGs_ls = CpGisland_ls,
        arrayType = "450k",
        returnAllCpGs = FALSE,
        output = "CpGs",
        nCores_int = 1
    )

    # --- Testing Association with Phenotype [lmmTestAllRegions] ---
    # Key functions: lmmTestAllRegions
    data(betasChr22_df)
    data(pheno_df)
    out_df <- lmmTestAllRegions(
        betas = betasChr22_df,
        region_ls = coMeth_ls,
        pheno_df = pheno_df,
        contPheno_char = "stage",
        covariates_char = NULL,
        modelType = "randCoef",
        arrayType = "450k"
    )

    # --- Annotating Results and Extracting Region Info [AnnotateResults, CpGsInfoOneRegion] ---
    # Key functions: AnnotateResults, CpGsInfoOneRegion
    data(betasChr22_df)
    data(pheno_df)
    outAnno_df <- AnnotateResults(
        lmmRes_df = out_df,
        arrayType = "450k"
    )
    outCpGs_df <- CpGsInfoOneRegion(
        regionName_char = "chr22:18268062-18268249",
        betas_df = betasChr22_df,
        pheno_df = pheno_df,
        contPheno_char = "stage",
        covariates_char = NULL,
        arrayType = "450k"
    )


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_comethdmr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_comethdmr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_comethdmr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_COMETHDMR:", paste0("    comethdmr: ", packageVersion("coMethDMR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_comethdmr_results.csv
    touch ${prefix}_comethdmr_output.rds
    echo "BIOC_COMETHDMR:" > versions.yml
    echo "    comethdmr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_COMETHDMR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_COMETHDMR(ch_input)

    emit:
    results  = BIOC_COMETHDMR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_COMETHDMR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_COMETHDMR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_COMETHDMR.out.versions  // channel: path(versions.yml)
}
