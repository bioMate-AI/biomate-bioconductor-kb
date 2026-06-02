#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: missMethyl
// Normalisation, testing for differential variability and differential methylation and gene set testin
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/missMethyl/inst/doc/missMethyl.R
// Upstream  : DMRcate, edgeR, limma, minfi, minfiData
// Downstream: methylationArrayAnalysis
//
// Install: BiocManager::install("missMethyl")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MISSMETHYL {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-missmethyl"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-missmethyl:1.40.3--r44_0' :
        'quay.io/biocontainers/bioconductor-missmethyl:1.40.3--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_missmethyl_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_missmethyl_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_missmethyl_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DGEList)
    library(RUVadj)
    library(RUVfit)
    library(SWAN)
    library(jsonlite)

    # --- Create DGEList count object [] ---
    # Key functions: DGEList, gsameth, topGSA
    hallmark <- readRDS(url("http://bioinf.wehi.edu.au/MSigDB/v7.1/Hs.h.all.v7.1.entrez.rds"))
    gsa <- gsameth(sig.cpg=sigCpGs, all.cpg=rownames(top), collection=hallmark)
    topGSA(gsa, n=10)
    # --- Filter by row sum threshold [] ---
    # Key functions: detectionP, rowSums, calcNormFactors
    isexpr <- rowSums(cpm(y)>1) >= 20
    hasannot <- rowSums(is.na(y$genes))==0
    dim(y)
    # --- Get top DE genes table (limma) [] ---
    # Key functions: topTable, lmFit, eBayes, makeContrasts
    design2 <- model.matrix(~0+group+id)
    fitvar.contr <- varFit(Mval, design=design2, coef=c(1,2))
    contr <- makeContrasts(groupcancer-groupnormal,levels=colnames(design2))
    # --- MDS plot of sample distances [] ---
    # Key functions: plotMDS
    par(mfrow=c(1,1))
    plotMDS(Mval, labels=targets$Sample_Name, col=as.integer(factor(targets$status)))
    legend("topleft",legend=c("Cancer","Normal"),pch=16,cex=1.2,col=1:2)
    # --- Annotation analysis [] ---
    # Key functions: annotation, preprocessRaw, SWAN, densityByProbeType, getMeth, getUnmeth, getBeta, stripchart
    library(IlluminaHumanMethylation450kanno.ilmn12.hg19)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_missmethyl_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_missmethyl_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_missmethyl_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MISSMETHYL:", paste0("    missmethyl: ", packageVersion("missMethyl"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_missmethyl_results.csv
    touch ${prefix}_missmethyl_output.rds
    echo "BIOC_MISSMETHYL:" > versions.yml
    echo "    missmethyl: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MISSMETHYL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MISSMETHYL(ch_input)

    emit:
    results  = BIOC_MISSMETHYL.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MISSMETHYL.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MISSMETHYL.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MISSMETHYL.out.versions  // channel: path(versions.yml)
}
