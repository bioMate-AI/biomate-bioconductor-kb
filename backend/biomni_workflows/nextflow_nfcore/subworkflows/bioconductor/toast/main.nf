#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: TOAST
// This package is devoted to analyzing high-throughput data (e.g. gene expression microarray, DNA meth
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/TOAST/inst/doc/TOAST.R
// Upstream  : EpiDISH
// Downstream: none
//
// Install: BiocManager::install("TOAST")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TOAST {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-toast"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-toast:1.20.0--r44_0' :
        'quay.io/biocontainers/bioconductor-toast:1.20.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_toast_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_toast_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_toast_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(TOAST)
    library(ChooseMarker)
    library(GetPrior)
    library(MDeconv)
    library(jsonlite)

    # --- Feature Selection ---
    # Key functions: findRefinx
    data("RA_100samples")
    Y_raw <- RA_100samples$Y_raw
    Blood_ref <- RA_100samples$Blood_ref
    refinx <- findRefinx(Y_raw, nmarker = 1000, sortBy = "var")
    Y <- Y_raw[refinx, ]
    Ref <- as.matrix(Blood_ref[refinx, ])

    # --- Reference-Free Deconvolution ---
    # Key functions: csDeconv, assignCellType
    data("RA_100samples")
    Y_raw <- RA_100samples$Y_raw
    outRF1 <- csDeconv(Y_raw, K = 6, TotalIter = 10, bound_negative = TRUE)
    mock_ref <- matrix(runif(nrow(outRF1$estProp) * 6), ncol = 6)
    estProp_aligned <- assignCellType(
        input = outRF1$estProp,
        reference = mock_ref
    )

    # --- Marker-Based Deconvolution ---
    # Key functions: ChooseMarker, GetPrior, MDeconv
    data("CBS_PBMC_array")
    CBS_mix <- CBS_PBMC_array$mixed_all
    LM_5 <- CBS_PBMC_array$LM_5
    CellType <- list(Bcells = 1, CD8T = 2, CD4T = 3, NK = 4, Monocytes = 5)
    myMarker <- ChooseMarker(
        LM_5, CellType, nMarkCT = 20,
        chooseSig = TRUE, verbose = FALSE
    )
    thisprior <- GetPrior("human pbmc")
    resCBS <- MDeconv(
        CBS_mix, myMarker, alpha = "human pbmc",
        epsilon = 1e-3, verbose = FALSE
    )

    # --- Cell-Type-Specific Differential Expression ---
    # Key functions: makeDesign, fitModel, csTest
    data("RA_100samples")
    Y_raw <- RA_100samples$Y_raw
    Pheno <- RA_100samples$Pheno
    design <- data.frame(disease = as.factor(Pheno$disease))
    Prop <- matrix(runif(ncol(Y_raw) * 6), ncol = 6)
    colnames(Prop) <- paste0("CellType", 1:6)
    Design_out <- makeDesign(design, Prop)
    fitted_model <- fitModel(Design_out, Y_raw)
    res_table <- csTest(fitted_model, coef = "disease", cell_type = "CellType1")

    # --- Hierarchical Differential Expression ---
    # Key functions: cedar
    data("RA_100samples")
    Y_raw <- RA_100samples$Y_raw
    Pheno <- RA_100samples$Pheno
    design <- data.frame(disease = as.factor(Pheno$disease))
    Prop <- matrix(runif(ncol(Y_raw) * 6), ncol = 6)
    colnames(Prop) <- paste0("CellType", 1:6)
    res_cedar <- cedar(
        Y_raw = Y_raw, prop = Prop, design.1 = design,
        factor.to.test = "disease", cutoff.tree = c("pval", 0.05),
        cutoff.prior.prob = c("pval", 0.05)
    )


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_toast_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_toast_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_toast_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TOAST:", paste0("    toast: ", packageVersion("TOAST"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_toast_results.csv
    touch ${prefix}_toast_output.rds
    echo "BIOC_TOAST:" > versions.yml
    echo "    toast: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TOAST_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TOAST(ch_input)

    emit:
    results  = BIOC_TOAST.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TOAST.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TOAST.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TOAST.out.versions  // channel: path(versions.yml)
}
