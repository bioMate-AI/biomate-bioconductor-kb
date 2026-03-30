#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: diggit
// Inference of Genetic Variants Driving Cellullar Phenotypes by the DIGGIT algorithm
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/diggit/inst/doc/diggit.R
// Upstream  : parallel
// Downstream: none
//
// Install: BiocManager::install("diggit")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DIGGIT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-diggit"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-diggit:1.38.0--r44_0' :
        'quay.io/biocontainers/bioconductor-diggit:1.38.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_diggit_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_diggit_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_diggit_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(OStype)
    library(RNGkind)
    library(jsonlite)

    # --- Info [] ---
    # Key functions: info
    # Initialization
    cores <- 3*(Sys.info()[1]!="Windows")+1
    # --- Data [] ---
    # Key functions: data
    data(gbm.expression, package="diggitdata")
    data(gbm.cnv, package="diggitdata")
    data(gbm.aracne, package="diggitdata")
    data(gbm.mindy, package="diggitdata")
    # --- Intersect [] ---
    # Key functions: intersect
    genes <- intersect(rownames(gbmExprs), rownames(gbmCNV))[1:1000]
    gbmCNV <- gbmCNV[match(genes, rownames(gbmCNV)), ]
    # --- Diggitclass [] ---
    # Key functions: diggitClass
    dobj <- diggitClass(expset=gbmExprs, cnv=gbmCNV, regulon=gbmTFregulon, mindy=gbmMindy)
    dobj
    # --- Fcnv [] ---
    # Key functions: fCNV, diggitFcnv
    dobj <- fCNV(dobj, method="spearman", verbose=FALSE)
    diggitFcnv(dobj)[1:5]
    head(dobj, 5)$fcnv
    # --- Rngkind [] ---
    # Key functions: RNGkind, OStype, stream, fCNV, diggitFcnv
    RNGkind("L'Ecuyer-CMRG")
    set.seed(1)
    #if(tools:::.OStype() == "unix") {
    #    mc.reset.stream()
    #}
    # --- Fcnv [] ---
    # Key functions: diggitCNV, exprs, intersect, diggitFcnv, fCNV
    tmp.cnv <- diggitCNV(dobj)
    tmp.exp <- exprs(exprs(dobj))
    samp <- intersect(colnames(tmp.cnv), colnames(tmp.exp))
    tmp.cnv <- tmp.cnv[, match(samp, colnames(tmp.cnv))]
    tmp.exp <- tmp.exp[, match(samp, colnames(tmp.exp))]
    # --- Conditional [] ---
    # Key functions: conditional
    dobj <- conditional(dobj, pheno="subtype", group1="MES", group2="PN", mr="STAT3",
                        cnv=cnvthr, cores=cores, verbose=FALSE)
    dobj

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_diggit_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_diggit_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_diggit_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DIGGIT:", paste0("    diggit: ", packageVersion("diggit"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_diggit_results.csv
    touch ${prefix}_diggit_output.rds
    echo "BIOC_DIGGIT:" > versions.yml
    echo "    diggit: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DIGGIT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DIGGIT(ch_input)

    emit:
    results  = BIOC_DIGGIT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DIGGIT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DIGGIT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DIGGIT.out.versions  // channel: path(versions.yml)
}
