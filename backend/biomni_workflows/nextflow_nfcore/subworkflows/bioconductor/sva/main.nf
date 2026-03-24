#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: sva
// The sva package contains functions for removing batch effects and other unwanted variation in high-t
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/sva/inst/doc/sva.R
// Upstream  : bladderbatch, limma, pamr, zebrafishRNASeq
// Downstream: DeMixT, IsoformSwitchAnalyzeR, SCAN.UPC, rnaseqGene, bapred
//
// Install: BiocManager::install("sva")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SVA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-sva"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-sva:3.54.0--r44_0' :
        'quay.io/biocontainers/bioconductor-sva:3.54.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_sva_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_sva_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_sva_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ComBat)
    library(ComBat_seq)
    library(jsonlite)

    # --- Input [] ---
    # Key functions: data
    library(sva)
    library(bladderbatch)
    data(bladderdata)
    library(pamr)
    library(limma)
    # --- Input [] ---
    # Key functions: pData
    pheno = pData(bladderEset)
    # --- Input [] ---
    # Key functions: exprs
    edata = exprs(bladderEset)
    # --- Input [] ---
    # Key functions: factor
    mod = model.matrix(~as.factor(cancer), data=pheno)
    # --- Input [] ---
    # Key functions: sv
    n.sv = num.sv(edata,mod,method="leek")
    n.sv
    # --- Input [] ---
    # Key functions: sva
    svobj = sva(edata,mod,mod0,n.sv=n.sv)
    # --- Input [] ---
    # Key functions: pvalue, adjust
    pValues = f.pvalue(edata,mod,mod0)
    qValues = p.adjust(pValues,method="BH")
    # --- Input [] ---
    # Key functions: lmFit
    fit = lmFit(edata,modSv)
    # --- Input [] ---
    # Key functions: fit
    contrast.matrix <- cbind("C1"=c(-1,1,0,rep(0,svobj$n.sv)),"C2"=c(0,-1,1,rep(0,svobj$n.sv)),"C3"=c(-1,0,1,rep(0,svobj$n.sv)))
    fitContrasts = contrasts.fit(fit,contrast.matrix)
    # --- Input [] ---
    # Key functions: eBayes, topTableF
    eb = eBayes(fitContrasts)
    topTableF(eb, adjust="BH")
    # --- Input [] ---
    # Key functions: ComBat
    combat_edata = ComBat(dat=edata, batch=batch, mod=modcombat, par.prior=TRUE, prior.plots=FALSE)
    # --- Input [] ---
    # Key functions: pvalue, adjust
    pValuesComBat = f.pvalue(combat_edata,mod,mod0)
    qValuesComBat = p.adjust(pValuesComBat,method="BH")
    # --- Input [] ---
    # Key functions: rnbinom, ComBat_seq
    count_matrix <- matrix(rnbinom(400, size=10, prob=0.1),
                           nrow=50, ncol=8)
    batch <- c(rep(1, 4), rep(2, 4))
    adjusted <- ComBat_seq(count_matrix, batch=batch, group=NULL)
    # --- Input [] ---
    # Key functions: ComBat_seq
    group <- rep(c(0,1), 4)
    adjusted_counts <- ComBat_seq(count_matrix, batch=batch,
                                  group=group)
    # --- Input [] ---
    # Key functions: factor, pvalue, adjust
    modBatch = model.matrix(~as.factor(cancer) + as.factor(batch),data=pheno)
    mod0Batch = model.matrix(~as.factor(batch),data=pheno)
    pValuesBatch = f.pvalue(edata,modBatch,mod0Batch)
    qValuesBatch = p.adjust(pValuesBatch,method="BH")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_sva_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_sva_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_sva_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SVA:", paste0("    sva: ", packageVersion("sva"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sva_results.csv
    touch ${prefix}_sva_output.rds
    echo "BIOC_SVA:" > versions.yml
    echo "    sva: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SVA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SVA(ch_input)

    emit:
    results  = BIOC_SVA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SVA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SVA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SVA.out.versions  // channel: path(versions.yml)
}
