#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: IMAS
// Integrative analysis of Multi-omics data for Alternative splicing.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/IMAS/inst/doc/IMAS.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("IMAS")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_IMAS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-imas"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-imas:1.30.0--r44_0' :
        'quay.io/biocontainers/bioconductor-imas:1.30.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_imas_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_imas_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_imas_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ASvisualization)
    library(ClinicAnalysis)
    library(CompGroupAlt)
    library(ExonsCluster)
    library(MEsQTLFinder)
    library(RatioFromReads)
    library(Splicingfinder)
    library(jsonlite)

    # --- Installation Of Imas [] ---
    # Key functions: requireNamespace, packages
    ## if (!requireNamespace("BiocManager", quietly=TRUE))
    ##     install.packages("BiocManager")
    ## BiocManager::install("IMAS")
    # --- Loading The Paths Of The Expression Data [] ---
    # Key functions: data, file
    data(bamfilestest)
    ext.dir <- system.file("extdata", package="IMAS")
    samplebamfiles[,"path"] <-
        paste(ext.dir,"/samplebam/",samplebamfiles[,"path"],".bam",sep="")
    # --- Loading The Snp Position Data [] ---
    # Key functions: data
    data(samplesnplocus)
    # --- Loading Methylation Position Data [] ---
    # Key functions: data
    data(samplemethyllocus)
    # --- Loading Clinical Information Data [] ---
    # Key functions: data
    data(sampleclinical)
    # --- Loading The Txdb Data [] ---
    # Key functions: files, loadDb
    sampledb <- list.files(ext.dir,pattern="DB",full.names=TRUE)
    transdb <- loadDb(sampledb)
    transdb
    # --- Splicingfinder Function [] ---
    # Key functions: Splicingfinder, ExonsCluster, slot
    ASdb <- Splicingfinder(GTFdb=transdb,calGene="ENSG00000082175",Ncor=1)
    ASdb <- ExonsCluster(ASdb,transdb)
    ASdb
    head(slot(ASdb,"SplicingModel")$"ES")
    # --- Ratiofromreads Function [] ---
    # Key functions: RatioFromReads, slot
    ASdb <- RatioFromReads(ASdb=ASdb,samplebamfiles,readsInfo="paired",
        readLen=50,inserSize=40,minr=3,CalIndex="ES3",Ncor=1)
    ASdb
    head(rbind(slot(ASdb,"Ratio")$"ES"[,1:20]))
    # --- Compgroupalt Function [] ---
    # Key functions: CompGroupAlt, slot
    ASdb <- CompGroupAlt(ASdb=ASdb,GroupSam=GroupSam,Ncor=1,CalIndex="ES3")
    ASdb
    head(slot(ASdb,"GroupDiff")$"ES")
    # --- Sqtlsfinder Function [] ---
    # Key functions: sQTLsFinder, slot
    ASdb <- sQTLsFinder(ASdb=ASdb,Total.snpdata=samplesnp,Total.snplocus=samplesnplocus,
        GroupSam=NULL,Ncor=1,CalIndex="ES3",method="lm")
    ASdb
    head(slot(ASdb,"sQTLs")$"ES")
    # --- Mesqtlfinder Function [] ---
    # Key functions: MEsQTLFinder, slot
    ASdb <- MEsQTLFinder(ASdb=ASdb,Total.Medata=sampleMedata,Total.Melocus=sampleMelocus,
        GroupSam=GroupSam,Ncor=1,CalIndex="ES3")
    ASdb
    head(slot(ASdb,"Me.sQTLs")$"ES")
    # --- Clinical Analysis Function [] ---
    # Key functions: ClinicAnalysis, slot
    ASdb <- ClinicAnalysis(ASdb=ASdb,ClinicalInfo=Clinical.data,Ncor=1,CalIndex="ES3")
    ASdb
    head(slot(ASdb,"Clinical")$"ES")
    # --- Visualization Function [] ---
    # Key functions: exonsBy, select, ASvisualization, tempdir
    exon.range <- exonsBy(transdb,by="tx")
    select.cns <- c("TXCHROM","TXNAME","GENEID","TXSTART","TXEND","TXSTRAND")
    txTable <- select(transdb, keys=names(exon.range),columns=select.cns,keytype="TXID")
    ASvisualization(ASdb,CalIndex="ES3",txTable,exon.range,samplesnp,samplesnplocus,
                    sampleMedata,sampleMelocus,GroupSam,Clinical.data,out.dir=tempdir())

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_imas_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_imas_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_imas_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_IMAS:", paste0("    imas: ", packageVersion("IMAS"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_imas_results.csv
    touch ${prefix}_imas_output.rds
    echo "BIOC_IMAS:" > versions.yml
    echo "    imas: 0.0.0" >> versions.yml
    """
}


workflow BIOC_IMAS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_IMAS(ch_input)

    emit:
    results  = BIOC_IMAS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_IMAS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_IMAS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_IMAS.out.versions  // channel: path(versions.yml)
}
