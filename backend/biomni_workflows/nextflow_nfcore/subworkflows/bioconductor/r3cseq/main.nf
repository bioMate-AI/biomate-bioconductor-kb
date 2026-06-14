#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: r3Cseq — three_c_seq_analysis_with_control
// Identify long-range chromatin interactions from 3C-seq data using an experimental sample and a control sample.
// Input: experiment.bam, control.bam
// Container: quay.io/biocontainers/bioconductor-r3cseq:1.56.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicAlignments, r3Cseq
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Initialize the r3Cseq object with viewpoint and restriction enzyme details
//  * 2. [Input & Preparation] Load raw reads into the object
//  * 3. [Core Analysis] Count reads per restriction fragment using getReadCountPerRestrictionFragment
//  * 4. [Input & Preparation] Normalize read counts using calculateRPM
//  * 5. [Core Analysis] Identify significant interaction regions using getInteractions
//  * 6. [Core Analysis] Extract interaction regions using expInteractionRegions and contrInteractionRegions
//  * 7. [Visualization & Output] Visualize interactions using plotting functions
//  * 8. [Core Analysis] Associate interaction signals with Refseq genes using getExpInteractionsInRefseq
//  * 9. [Visualization & Output] Export results using export3Cseq2bedGraph or generate3CseqReport

nextflow.enable.dsl = 2

process BIOC_R3CSEQ_THREE_C_SEQ_ANALYSIS_WITH_CONTROL {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("r3Cseq", "GenomicAlignments")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required libraries
    library(r3Cseq)
    library(GenomicAlignments)
    
    # Read user input BAM files
    message("Reading experiment.bam...")
    exp.GRanges <- granges(readGAlignments("experiment.bam"))
    
    message("Reading control.bam...")
    contr.GRanges <- granges(readGAlignments("control.bam"))
    
    # Initialize r3Cseq object
    my3Cseq.obj<-new("r3Cseq",organismName='mm9',isControlInvolved=TRUE,
    viewpoint_chromosome='chr10',viewpoint_primer_forward='TCTTTGTTTGATGGCATCTGTT',
    viewpoint_primer_reverse='AAAGGGGAGGAGAAGGAGGT',expLabel="Myb_prom_FL",
    contrLabel="MYb_prom_FB",restrictionEnzyme='HindIII')
    
    # Assign raw data
    expRawData(my3Cseq.obj)<-exp.GRanges
    contrRawData(my3Cseq.obj)<-contr.GRanges	
    
    # Print object summary
    print(my3Cseq.obj)
    
    # Count reads per restriction fragment
    getReadCountPerRestrictionFragment(my3Cseq.obj)
    
    # Normalize read counts
    calculateRPM(my3Cseq.obj)	
    
    # Identify significant interactions
    getInteractions(my3Cseq.obj,fdr=0.05)	
    
    # Extract interaction regions
    fetal.liver.interactions<-expInteractionRegions(my3Cseq.obj)
    print(fetal.liver.interactions)
    
    fetal.brain.interactions<-contrInteractionRegions(my3Cseq.obj)
    print(fetal.brain.interactions)
    
    # Get viewpoint
    viewpoint<-getViewpoint(my3Cseq.obj)
    print(viewpoint)
    
    # Plotting and saving visualizations to PDF
    pdf("r3Cseq_plots.pdf", width = 10, height = 8)
    plotOverviewInteractions(my3Cseq.obj)	
    plotInteractionsNearViewpoint(my3Cseq.obj)	
    plotInteractionsPerChromosome(my3Cseq.obj,"chr10")	
    dev.off()
    
    # Associate interaction signals with Refseq genes
    detected_genes<-getExpInteractionsInRefseq(my3Cseq.obj)
    print(head(detected_genes))
    
    # Export results to bedGraph
    export3Cseq2bedGraph(my3Cseq.obj)	
    
    # Generate report (wrapped in tryCatch in case of missing LaTeX dependencies)
    tryCatch({
      generate3CseqReport(my3Cseq.obj)
    }, error = function(e) {
      message("Skipping PDF report generation: ", e\$message)
    })
    
    # Save outputs to files
    write.csv(as.data.frame(fetal.liver.interactions), "fetal_liver_interactions.csv", row.names = FALSE)
    write.csv(as.data.frame(fetal.brain.interactions), "fetal_brain_interactions.csv", row.names = FALSE)
    write.csv(detected_genes, "detected_genes.csv", row.names = FALSE)
    saveRDS(my3Cseq.obj, "my3Cseq_object.rds")
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_R3CSEQ_THREE_C_SEQ_ANALYSIS_WITH_CONTROL":',
        paste0('    r3Cseq: ', as.character(packageVersion('r3Cseq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_three_c_seq_analysis_with_control.csv versions.yml
    """
}

workflow BIOC_R3CSEQ_THREE_C_SEQ_ANALYSIS_WITH_CONTROL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ experiment.bam, control.bam ] ]

    main:
    BIOC_R3CSEQ_THREE_C_SEQ_ANALYSIS_WITH_CONTROL(ch_input)

    emit:
    tables   = BIOC_R3CSEQ_THREE_C_SEQ_ANALYSIS_WITH_CONTROL.out.tables
    plots    = BIOC_R3CSEQ_THREE_C_SEQ_ANALYSIS_WITH_CONTROL.out.plots
    objects  = BIOC_R3CSEQ_THREE_C_SEQ_ANALYSIS_WITH_CONTROL.out.objects
    versions = BIOC_R3CSEQ_THREE_C_SEQ_ANALYSIS_WITH_CONTROL.out.versions
}
