#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GlobalAncova
// The association between a variable of interest (e.g. two groups) and the global pattern of a group o
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GlobalAncova/inst/doc/GlobalAncova.R
// Upstream  : Biobase, Rgraphviz, globaltest, golubEsets, vsn
// Downstream: none
//
// Install: BiocManager::install("GlobalAncova")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GLOBALANCOVA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-globalancova"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-globalancova:4.24.0--r44_0' :
        'quay.io/biocontainers/bioconductor-globalancova:4.24.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_globalancova_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_globalancova_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_globalancova_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GABroad)
    library(GAGO)
    library(GlobalAncova)
    library(jsonlite)

    # --- Initialize [] ---
    # Key functions: justvsn
    library(GlobalAncova)
    library(globaltest)
    library(golubEsets)
    library(hu6800.db)
    library(vsn)
    # --- All [] ---
    # Key functions: GlobalAncova, exprs
    gr <- as.numeric(golubX$ALL.AML=="ALL")
    ga.all <- GlobalAncova(xx=exprs(golubX), group=gr, covars=NULL, perm=100)
    # --- All2 [] ---
    # Key functions: GlobalAncova, exprs, pData
    ## GlobalAncova(xx=exprs(golubX), formula.full=~ALL.AML, formula.red=~1,
    ##              model.dat=pData(golubX), perm=100)
    ## GlobalAncova(xx=exprs(golubX), formula.full=~ALL.AML, test.terms="ALL.AMLAML",
    ##              model.dat=pData(golubX), perm=100)
    # --- gt [] ---
    # Key functions: gt
    gt.all <- gt(ALL.AML, golubX)
    # --- Cellcycle [] ---
    # Key functions: GlobalAncova, exprs
    ga.cc <- GlobalAncova(xx=exprs(golubX), group=gr, test.genes=cellcycle,
                          method="both", perm=1000)
    ga.cc
    # --- gt [] ---
    # Key functions: gt
    gt.cc <- gt(ALL.AML, golubX, subsets=cellcycle)
    gt.cc
    # --- Adjust [] ---
    # Key functions: GlobalAncova, exprs
    ga.cc.BMPB <- GlobalAncova(xx=exprs(golubX), group=gr, covars=golubX$BM.PB,
                               test.genes=cellcycle, method="both", perm=1000)
    ga.cc.BMPB
    # --- gt [] ---
    # Key functions: gt
    gt.cc.BMPB <- gt(ALL.AML ~ BM.PB, golubX, subsets=cellcycle)
    gt.cc.BMPB
    # --- Globalancova.Rnw:366 369 [] ---
    # Key functions: data
    data(vantVeer)
    data(phenodata)
    data(pathways)
    # --- Vv [] ---
    # Key functions: data
    data(vantVeer)
    data(phenodata)
    data(pathways)
    metastases <- phenodata$metastases
    p53 <- pathways$p53_signalling
    # --- Global Ancova [] ---
    # Key functions: GlobalAncova
    vV.1 <- GlobalAncova(xx=vantVeer, group=metastases, test.genes=p53,
                         method="both", perm=1000)
    vV.1
    # --- Grade [] ---
    # Key functions: GlobalAncova
    vV.3 <- GlobalAncova(xx=vantVeer, formula.full=~grade, formula.red=~1,
              model.dat=phenodata, test.genes=p53, method="both", perm=1000)
    vV.3
    # --- Interact [] ---
    # Key functions: frame, GlobalAncova
    signature.gene <- "AL137718"
    model <- data.frame(phenodata, signature.gene=vantVeer[signature.gene, ])
    vV.4 <- GlobalAncova(xx=vantVeer, formula.full=~signature.gene + ERstatus,
                         formula.red=~ERstatus, model.dat=model, test.genes=p53,
                         method="both", perm=1000)
    # --- Coexpr [] ---
    # Key functions: GlobalAncova
    vV.5 <- GlobalAncova(xx=vantVeer, formula.full=~metastases + signature.gene + ERstatus,
                         formula.red=~metastases + ERstatus, model.dat=model,
                         test.genes=p53, method="both", perm=1000)
    vV.5
    # --- Diffcoexpr [] ---
    # Key functions: GlobalAncova
    vV.6 <- GlobalAncova(xx=vantVeer, formula.full=~metastases * signature.gene + ERstatus,
                         formula.red=~metastases + signature.gene + ERstatus,
                         model.dat=model, test.genes=p53, method="both", perm=1000)
    vV.6

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_globalancova_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_globalancova_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_globalancova_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GLOBALANCOVA:", paste0("    globalancova: ", packageVersion("GlobalAncova"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_globalancova_results.csv
    touch ${prefix}_globalancova_output.rds
    echo "BIOC_GLOBALANCOVA:" > versions.yml
    echo "    globalancova: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GLOBALANCOVA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GLOBALANCOVA(ch_input)

    emit:
    results  = BIOC_GLOBALANCOVA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GLOBALANCOVA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GLOBALANCOVA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GLOBALANCOVA.out.versions  // channel: path(versions.yml)
}
