#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: biomvRCNS — acgh_copy_number_segmentation
// Segment array CGH (aCGH) data to identify genomic regions of copy number deletion, duplication, or neutrality across multiple samples.
// Input: coriell.txt
// Container: quay.io/biocontainers/bioconductor-biomvrcns:1.50.0--r45h01b2380_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, biomvRCNS
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load data and construct a sorted GRanges object
//  * 2. [Core Analysis] Run the Hidden Semi-Markov Model (HSMM) segmentation using biomvRhsmm
//  * 3. [Visualization & Output] Visualize the segmentation results using biomvRGviz
//  * 4. [Core Analysis] Run alternative homogeneous segmentation using biomvRseg
//  * 5. [Core Analysis] Run alternative max-gap-min-run segmentation using biomvRmgmr

nextflow.enable.dsl = 2

process BIOC_BIOMVRCNS_ACGH_COPY_NUMBER_SEGMENTATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
        
    # Load required libraries
    library(biomvRCNS)
    library(GenomicRanges)
    
    # 1. Load data and construct a sorted GRanges object
    # Read the user input file 'coriell.txt' from the working directory
    coriell <- read.table("coriell.txt", header = TRUE, stringsAsFactors = FALSE)
    
    # Construct GRanges object exactly as documented
    xgr<-GRanges(seqnames=coriell[,2], 
    	IRanges(start=coriell[,3], width=1, names=coriell[,1]))
    values(xgr)<-DataFrame(coriell[,4:5], row.names=NULL)
    xgr<-sort(xgr)
    head(xgr, n=3)
    
    # 2. Run the Hidden Semi-Markov Model (HSMM) segmentation using biomvRhsmm
    rhsmm<-biomvRhsmm(x=xgr, maxbp=1E5, J=3, soj.type='gamma', 
    	com.emis=T, emis.type='norm', prior.m='quantile', grp=c(1,2))
    show(rhsmm)
    
    # 3. Visualize the segmentation results using biomvRGviz
    # We wrap the visualization in a PDF device to save the output plot while keeping tofile=FALSE
    sample_name <- colnames(coriell)[4]
    chrom_name <- as.character(seqnames(xgr)[1])
    
    pdf("hsmm_segmentation_plot.pdf", width = 10, height = 6)
    obj<-biomvRGviz(exprgr=xgr[seqnames(xgr)==chrom_name, sample_name], 
    	seggr=rhsmm@res[mcols(rhsmm@res)[,'SAMPLE']==sample_name], tofile=FALSE)
    dev.off()
    
    # 4. Run alternative homogeneous segmentation using biomvRseg
    rseg<-biomvRseg(x=xgr, maxbp=4E4, maxseg=10, family='norm', grp=c(1,2))
    head(rseg@res)
    
    # 5. Run alternative max-gap-min-run segmentation using biomvRmgmr
    rmgmrh<-biomvRmgmr(xgr, q=0.9, high=T, maxgap=1000, minrun=2500, grp=c(1,2))
    rmgmrl<-biomvRmgmr(xgr, q=0.1, high=F, maxgap=1000, minrun=2500, grp=c(1,2))
    res<-c(rmgmrh@res, rmgmrl@res)
    
    # Save meaningful results to output files
    saveRDS(rhsmm, "rhsmm_model.rds")
    write.csv(as.data.frame(rhsmm@res), "rhsmm_segments.csv", row.names = FALSE)
    
    saveRDS(rseg, "rseg_model.rds")
    write.csv(as.data.frame(rseg@res), "rseg_segments.csv", row.names = FALSE)
    
    saveRDS(res, "mgmr_segments.rds")
    write.csv(as.data.frame(res), "mgmr_segments.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_BIOMVRCNS_ACGH_COPY_NUMBER_SEGMENTATION":',
        paste0('    biomvRCNS: ', as.character(packageVersion('biomvRCNS')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_acgh_copy_number_segmentation.csv versions.yml
    """
}

workflow BIOC_BIOMVRCNS_ACGH_COPY_NUMBER_SEGMENTATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ coriell.txt ] ]

    main:
    BIOC_BIOMVRCNS_ACGH_COPY_NUMBER_SEGMENTATION(ch_input)

    emit:
    tables   = BIOC_BIOMVRCNS_ACGH_COPY_NUMBER_SEGMENTATION.out.tables
    plots    = BIOC_BIOMVRCNS_ACGH_COPY_NUMBER_SEGMENTATION.out.plots
    objects  = BIOC_BIOMVRCNS_ACGH_COPY_NUMBER_SEGMENTATION.out.objects
    versions = BIOC_BIOMVRCNS_ACGH_COPY_NUMBER_SEGMENTATION.out.versions
}
