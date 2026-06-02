#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: EventPointer
// EventPointer is an R package to identify alternative splicing events that involve either simple (cas
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/EventPointer/inst/doc/EventPointer.R
// Upstream  : BiocManager, Matrix, biomaRt, dplyr, kableExtra
// Downstream: none
//
// Install: BiocManager::install("EventPointer")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_EVENTPOINTER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-eventpointer"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-eventpointer:3.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-eventpointer:3.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_eventpointer_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_eventpointer_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_eventpointer_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CDFfromGTF)
    library(CDFfromGTF_Multipath)
    library(EventDetection)
    library(EventDetectionMultipath)
    library(EventDetection_transcriptome)
    library(EventPointer)
    library(EventPointer_Bootstraps)
    library(EventPointer_IGV)
    library(EventPointer_RNASeq)
    library(EventPointer_RNASeq_IGV)
    library(jsonlite)

    # --- tempdir [] ---
    # Key functions: tempdir, CDFfromGTF
    PathFiles<-system.file("extdata",package="EventPointer")
    DONSON_GTF<-paste(PathFiles,"/DONSON.gtf",sep="")
    PSRProbes<-paste(PathFiles,"/PSR_Probes.txt",sep="")
    # --- timestamp On [] ---
    # Key functions: timestampOn, NormExpBackgroundCorrection, process, QuantileNormalization, ExonRmaPlm
    verbose <- Arguments$getVerbose(-8);
    timestampOn(verbose);
    cdfG <- AffymetrixCdfFile$byChipType(cdfGFile)
    # --- EP arrays [] ---
    # Key functions: EventPointer
    data(ArraysData)
    Dmatrix<-matrix(c(1,1,1,1,0,0,1,1),nrow=4,ncol=2,byrow=FALSE)
    Cmatrix<-t(t(c(0,1)))
    # --- EP Arrays Res Table [] ---
    # Key functions: kable
    kable(Events[1:5,],digits=5,row.names=TRUE,align="c",caption = "Table 1: EventPointer Arrays results")
    # --- Arrays IGV [] ---
    # Key functions: tempdir, EventPointer_IGV
    DONSON_GTF<-paste(PathFiles,"/DONSON.gtf",sep="")
    PSRProbes<-paste(PathFiles,"/PSR_Probes.txt",sep="")
    JunctionProbes<-paste(PathFiles,"/Junction_Probes.txt",sep="")
    # --- Prepare Bam_ E P [] ---
    # Key functions: PrepareBam_EP
    PathToSamples <- system.file("extdata/bams", package = "SGSeq")
    PathToGTF<-paste(system.file("extdata",package="EventPointer"),"/FBXO31.gtf",sep="")
    SG_RNASeq<-PrepareBam_EP(Samples=Samples,
    # --- tempdir [] ---
    # Key functions: tempdir, EventDetection
    data(SG_RNASeq)
    TxtPath<-tempdir()
    AllEvents_RNASeq<-EventDetection(SG_RNASeq,cores=1,Path=TxtPath)
    # --- EP RNASeq [] ---
    # Key functions: EventPointer_RNASeq
    Dmatrix<-matrix(c(1,1,1,1,1,1,1,1,0,0,0,0,1,1,1,1),ncol=2,byrow=FALSE)
    Cmatrix<-t(t(c(0,1)))
    Events <- EventPointer_RNASeq(AllEvents_RNASeq,Dmatrix,Cmatrix,Statistic="LogFC",PSI=TRUE)
    # --- EP RNASeq Res Table [] ---
    # Key functions: kable
    kable(Events[1:5,],digits=5,row.names=TRUE,align="c",caption = "Table 2: EventPointer RNASeq results")
    # --- RNAS IGV [] ---
    # Key functions: tempdir, EventPointer_RNASeq_IGV
    EventsTxt<-paste(system.file("extdata",package="EventPointer"),"/EventsFound_RNASeq.txt",sep="")
    PathGTF<-tempdir()
    EventPointer_RNASeq_IGV(Events,SG_RNASeq,EventsTxt,PathGTF)
    # --- GTFfGTF 2 [] ---
    # Key functions: EventDetection_transcriptome
    EventXtrans <- EventDetection_transcriptome(inputFile = inputFile,
    # --- getbootstrapdata [] ---
    # Key functions: getbootstrapdata
    PathSamples<-system.file("extdata",package="EventPointer")
    PathSamples <- paste0(PathSamples,"/output")
    PathSamples <- dir(PathSamples,full.names = TRUE)
    # --- dir [] ---
    # Key functions: dir
    PathFiles <- system.file("extdata",package="EventPointer")
    filesnames <- dir(paste0(PathFiles,"/output"))
    PathFiles <- dir(paste0(PathFiles,"/output"),full.names = TRUE)
    # --- PSI Statistic [] ---
    # Key functions: GetPSI_FromTranRef
    rownames(RNASeq) <- sapply(strsplit(rownames(RNASeq),"\\|"),function(X) return(X[1]))
    RNASeq<-as.matrix(RNASeq) #must be a matrix variable
    PSIss_nb <- GetPSI_FromTranRef(PathsxTranscript = EventXtrans,
    # --- psi with bootstrap [] ---
    # Key functions: GetPSI_FromTranRef
    rownames(data_exp[[1]]) <- sapply(strsplit(rownames(data_exp[[1]]),"\\|"),function(X) return(X[1]))
    PSIss <- GetPSI_FromTranRef(PathsxTranscript = EventXtrans,

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_eventpointer_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_eventpointer_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_eventpointer_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_EVENTPOINTER:", paste0("    eventpointer: ", packageVersion("EventPointer"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_eventpointer_results.csv
    touch ${prefix}_eventpointer_output.rds
    echo "BIOC_EVENTPOINTER:" > versions.yml
    echo "    eventpointer: 0.0.0" >> versions.yml
    """
}


workflow BIOC_EVENTPOINTER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_EVENTPOINTER(ch_input)

    emit:
    results  = BIOC_EVENTPOINTER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_EVENTPOINTER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_EVENTPOINTER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_EVENTPOINTER.out.versions  // channel: path(versions.yml)
}
