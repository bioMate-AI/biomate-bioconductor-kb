#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MBttest
// MBttest method was developed from beta t-test method of Baggerly et al(2003). Compared to baySeq (Ha
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MBttest/inst/doc/MBttest.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("MBttest")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MBTTEST {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mbttest"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-mbttest:1.34.0--r44_0' :
        'quay.io/biocontainers/bioconductor-mbttest:1.34.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_mbttest_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mbttest_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mbttest_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MBttest)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    data(jkttcell)
    jkttcell[1:10,]
    # --- Simulat [] ---
    # Key functions: simulat
    sjknull1<-simulat(yy=jkttcell[1:500,], nci=7,r1=3,r2=3,p=0, q=0.2)
    # --- Smbetattest [] ---
    # Key functions: smbetattest
    mysim1<-smbetattest(X=sjknull1,na=3,nb=3,alpha=0.05)
    # --- Mbetattest [] ---
    # Key functions: mbetattest
    res<-mbetattest(X=jkttcell[1:1000,],na=3,nb=3,W=1,alpha=0.05,file="jurkat_NS_48h_tag_mbetattest.csv")
    # --- Maplot [] ---
    # Key functions: maplot
    maplot(dat=dat,r1=3,r2=3,TT=350,matitle="MA plot")
    # --- Figmaplot [] ---
    # Key functions: maplot
    maplot(dat=dat,r1=3,r2=3,TT=350,matitle="MA plot")
    # --- Maplot50 [] ---
    # Key functions: maplot
    maplot(dat=dat,r1=3,r2=3,TT=50,matitle="MA plot")
    # --- Figmaplot50 [] ---
    # Key functions: maplot
    maplot(dat=dat,r1=3,r2=3,TT=50,matitle="MA plot")
    # --- Heatmapwithtree [] ---
    # Key functions: myheatmap
    myheatmap(dat=dat,r1=3,r2=3,maptitle="Jurkat T-cell heatmap2")
    # --- Figheatmapwithtree [] ---
    # Key functions: myheatmap
    myheatmap(dat=dat,r1=3,r2=3,maptitle="Jurkat T-cell heatmap2")
    # --- Heatmapwithouttree [] ---
    # Key functions: myheatmap
    myheatmap(dat=dat,r1=3,r2=3,tree="none",maptitle="Jurkat T-cell heatmap3")
    # --- Figheatmapwithouttree [] ---
    # Key functions: myheatmap
    myheatmap(dat=dat,r1=3,r2=3,tree="none",maptitle="Jurkat T-cell heatmap3")
    # --- Heatmapwithcoltree [] ---
    # Key functions: myheatmap
    myheatmap(dat=dat,r1=3,r2=3,colrs="redblue", tree="column",
    method="pearson", maptitle="Jurkat T-cell heatmap")
    # --- Figheatmapwithcoltree [] ---
    # Key functions: myheatmap
    myheatmap(dat=dat,r1=3,r2=3,colrs="redblue", tree="column",
    method="pearson", maptitle="Jurkat T-cell heatmap")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_mbttest_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_mbttest_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_mbttest_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MBTTEST:", paste0("    mbttest: ", packageVersion("MBttest"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mbttest_results.csv
    touch ${prefix}_mbttest_output.rds
    echo "BIOC_MBTTEST:" > versions.yml
    echo "    mbttest: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MBTTEST_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MBTTEST(ch_input)

    emit:
    results  = BIOC_MBTTEST.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MBTTEST.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MBTTEST.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MBTTEST.out.versions  // channel: path(versions.yml)
}
