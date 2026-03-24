#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: coGPS
// Gene Set Enrichment Analysis of P-value based statistics for outlier gene detection in dataset merge
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/coGPS/inst/doc/coGPS.R
// Upstream  : limma
// Downstream: none
//
// Install: BiocManager::install("coGPS")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_COGPS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cogps"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cogps:1.50.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cogps:1.50.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cogps_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cogps_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cogps_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(PCOPA)
    library(PatientSpecificGeneList)
    library(PlotTopPCOPA)
    library(jsonlite)

    # --- Loading [] ---
    # Key functions: data
    library(coGPS)
    data(Exon_exprs_matched)
    data(Methy_exprs_matched)
    data(CNV_exprs_matched)
    data(Exon_classlab_matched)
    # --- Transforming [] ---
    # Key functions: unlist
    #exprslist[[i]]$exprs should be in matrix format
    Exon_exprs<-as.matrix(Exon_exprs_matched)
    Methy_exprs<-as.matrix(Methy_exprs_matched)
    CNV_exprs<-as.matrix(CNV_exprs_matched)
    #exprslist[[i]]$classlab should be in vector format
    # --- Subtypeanalysis [] ---
    # Key functions: PCOPA
    a7<-PCOPA(trylist,0.05,side=c("up","down","up"),type="subtype")
    # --- Uniformanalysis [] ---
    # Key functions: PCOPA
    a8<-PCOPA(trylist,0.05,side=c("up","down","up"),type="uniform")
    # --- Plotpcopa [] ---
    # Key functions: PlotTopPCOPA
    PlotTopPCOPA(trylist,a8,topcut=1,typelist=c("Exon","Methy","CNV"))
    # --- Plottoppcopa [] ---
    # Key functions: PlotTopPCOPA
    PlotTopPCOPA(trylist,a8,topcut=1,typelist=c("Exon","Methy","CNV"))
    # --- Permutation [] ---
    # Key functions: permCOPA
    perma7<-permCOPA(trylist,0.05,side=c("up","down","up"),type="subtype",perms=2)
    # --- Gsa [] ---
    # Key functions: na
    library(limma)
    data(human_c1)
    genename<-rownames(Exon_exprs)
    test_set1_a7<-rep(1,length(Hs.gmtl.c1))
    for(i in 1:length(Hs.gmtl.c1))
    # --- Patientspecific [] ---
    # Key functions: PatientSpecificGeneList
    IndividualList7<-PatientSpecificGeneList(trylist,0.05,side=c("down","up","down"),
    type="subtype",TopGeneNum=100)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cogps_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cogps_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cogps_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_COGPS:", paste0("    cogps: ", packageVersion("coGPS"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cogps_results.csv
    touch ${prefix}_cogps_output.rds
    echo "BIOC_COGPS:" > versions.yml
    echo "    cogps: 0.0.0" >> versions.yml
    """
}


workflow BIOC_COGPS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_COGPS(ch_input)

    emit:
    results  = BIOC_COGPS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_COGPS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_COGPS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_COGPS.out.versions  // channel: path(versions.yml)
}
