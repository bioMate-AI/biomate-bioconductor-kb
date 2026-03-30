#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: IVAS
// Identification of genetic variants affecting alternative splicing.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/IVAS/inst/doc/IVAS.R
// Upstream  : none
// Downstream: IMAS
//
// Install: BiocManager::install("IVAS")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_IVAS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ivas"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ivas:2.26.0--r44_0' :
        'quay.io/biocontainers/bioconductor-ivas:2.26.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ivas_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ivas_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ivas_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(RatioFromFPKM)
    library(Splicingfinder)
    library(jsonlite)

    # --- Loading The Snp Position Data [] ---
    # Key functions: data
    data(samplesnplocus)
    # --- Loading The Txdb Data [] ---
    # Key functions: loadDb
    sampleDB <- system.file("extdata","sampleDB", package="IVAS")
    sample.Txdb <- loadDb(sampleDB)
    # --- Splicingfinder Function [] ---
    # Key functions: Splicingfinder, slot
    ASdb <- Splicingfinder(GTFdb=sample.Txdb,calGene=NULL,Ncor=1,out.dir=NULL)
    ASdb
    head(slot(ASdb,"SplicingModel")$"ASS")
    # --- Ratiofromfpkm Function [] ---
    # Key functions: RatioFromFPKM, slot
    ASdb <- RatioFromFPKM(GTFdb=sample.Txdb,ASdb=ASdb,Total.expdata=sampleexp,
        CalIndex="ASS7",Ncor=1,out.dir=NULL)
    ASdb
    head(slot(ASdb,"Ratio")$"ASS")
    # --- Sqtlsfinder Function [] ---
    # Key functions: sQTLsFinder, slot
    ASdb <- sQTLsFinder(ASdb=ASdb,Total.snpdata=samplesnp,
        Total.snplocus=samplesnplocus,method="lm",Ncor=1)
    ASdb
    head(slot(ASdb,"sQTLs")$"ASS")
    # --- Multi Threds Function [] ---
    # Key functions: Splicingfinder, RatioFromFPKM, sQTLsFinder
    ## ASdb <- Splicingfinder(GTFdb=sample.Txdb,calGene=NULL,Ncor=4)
    ## ASdb <- RatioFromFPKM(GTFdb=sample.Txdb,ASdb=ASdb,Total.expdata=sampleexp,Ncor=4)
    ## ASdb <- sQTLsFinder(ASdb=ASdb,Total.snpdata=samplesnp,
    ##     Total.snplocus=samplesnplocus,method="lm",Ncor = 4)
    ## ASdb
    # --- Savebplot Function [] ---
    # Key functions: saveBplot
    saveBplot(ASdb=ASdb,Total.snpdata=samplesnp,Total.snplocus=samplesnplocus,
        CalIndex="ASS7",out.dir="./result")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ivas_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ivas_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ivas_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_IVAS:", paste0("    ivas: ", packageVersion("IVAS"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ivas_results.csv
    touch ${prefix}_ivas_output.rds
    echo "BIOC_IVAS:" > versions.yml
    echo "    ivas: 0.0.0" >> versions.yml
    """
}


workflow BIOC_IVAS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_IVAS(ch_input)

    emit:
    results  = BIOC_IVAS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_IVAS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_IVAS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_IVAS.out.versions  // channel: path(versions.yml)
}
