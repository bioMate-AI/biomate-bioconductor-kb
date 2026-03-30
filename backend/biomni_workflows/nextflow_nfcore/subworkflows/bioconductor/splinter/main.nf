#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SPLINTER
// Provides tools to analyze alternative splicing sites, interpret outcomes based on sequence informati
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SPLINTER/inst/doc/vignette.R
// Upstream  : GenomicFeatures, txdbmaker
// Downstream: none
//
// Install: BiocManager::install("SPLINTER")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SPLINTER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-splinter"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-splinter:1.32.0--r44_0' :
        'quay.io/biocontainers/bioconductor-splinter:1.32.0--r44_0'}"

    input:
    tuple val(meta), path(input_file)

    output:
    tuple val(meta), path("${meta.id}_splinter_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_splinter_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_splinter_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SPLINTER)
    library(jsonlite)

    # --- Addensemblannotation [] ---
    # Key functions: addEnsemblAnnotation, with
    ---------------------------------------------------------------------
    splice_data<-addEnsemblAnnotation(data=splice_data,species="mmusculus")
    # (Optional) Sorting the dataframe, if you have supporting statistical information
    splice_data$data<-splice_data$data[with(splice_data$data,order(FDR,-IncLevelDifference)),]
    head(splice_data$data[,c(1:10)])
    # --- Findtx [] ---
    # Key functions: findTX
    ---------------------------------------------------------------------
    valid_tx <- findTX(id=single_record$ID,tx=theexons,db=txdb)
    valid_cds<- findTX(id=single_record$ID,tx=thecds,db=txdb)
    # --- Makeroi [] ---
    # Key functions: makeROI
    ---------------------------------------------------------------------
    roi <- makeROI(single_record,type="SE")
    roi
    # --- Findcompatibleevents [] ---
    # Key functions: findCompatibleEvents
    ---------------------------------------------------------------------
    compatible_tx<- findCompatibleEvents(valid_tx,roi=roi,verbose=TRUE)
    compatible_cds<- findCompatibleEvents(valid_cds,valid_tx,roi=roi,verbose=TRUE)
    # --- Removeregion [] ---
    # Key functions: removeRegion
    ---------------------------------------------------------------------
    region_minus_exon <-removeRegion(compatible_cds$hits[[1]],roi)
    # --- Insertregion [] ---
    # Key functions: insertRegion
    ---------------------------------------------------------------------
    # Not relevant for this Prmt5 skipped exon example
    region_plus_exon <-insertRegion(region_minus_exon,roi)
    # --- Eventoutcomecompare [] ---
    # Key functions: eventOutcomeCompare
    ---------------------------------------------------------------------
    event<-eventOutcomeCompare(seq1=compatible_cds$hits[[1]],seq2=region_minus_exon,
                        genome=bsgenome,direction=TRUE,fullseq=FALSE)
    event
    # --- Getregiondna [] ---
    # Key functions: getRegionDNA
    ---------------------------------------------------------------------
    aa<-getRegionDNA(roi,bsgenome)
    aa
    # --- Frame [] ---
    # Key functions: frame
    ---------------------------------------------------------------------
    primers <- data.frame(PRIMER_LEFT_SEQUENCE="ACTTTCGGACTCTGTGTGACT",
                          PRIMER_RIGHT_SEQUENCE="TCATAGGCATTGGGTGGAGG",
                          stringsAsFactors=FALSE)
    # --- Checkprimer [] ---
    # Key functions: checkPrimer
    ---------------------------------------------------------------------
    cp<-checkPrimer(primers[1,],bsgenome,roi)
    cp
    # --- Getpcrsizes [] ---
    # Key functions: getPCRsizes, removeRegion
    ---------------------------------------------------------------------
    pcr_result1<-getPCRsizes(cp,theexons)
    pcr_result1
    tx_minus_exon <-removeRegion(compatible_tx$hits[[1]],roi)
    pcr_result2<-getPCRsizes(cp,tx_minus_exon)
    # --- Splitpcrhit [] ---
    # Key functions: splitPCRhit
    ---------------------------------------------------------------------
    relevant_pcr_bands<-splitPCRhit(pcr_result1,compatible_tx)
    relevant_pcr_bands

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_splinter_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_splinter_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_splinter_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SPLINTER:", paste0("    splinter: ", packageVersion("SPLINTER"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_splinter_results.csv
    touch ${prefix}_splinter_output.rds
    echo "BIOC_SPLINTER:" > versions.yml
    echo "    splinter: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SPLINTER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input_file) ]

    main:
    BIOC_SPLINTER(ch_input)

    emit:
    results  = BIOC_SPLINTER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SPLINTER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SPLINTER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SPLINTER.out.versions  // channel: path(versions.yml)
}
