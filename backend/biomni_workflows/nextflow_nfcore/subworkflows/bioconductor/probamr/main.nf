#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: proBAMr — probam_generation
// Map peptide-spectrum matches (PSMs) to genomic coordinates and generate a SAM file using GENCODE annotations.
// Input: test.gtf, coding_seq.fasta, pro_seq.fasta, passedPSM.tab
// Container: quay.io/biocontainers/bioconductor-probamr:1.44.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: proBAMr
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Prepare annotation files from GENCODE GTF and FASTA files using PrepareAnnotationGENCODE
//  * 2. [Input & Preparation] Load the prepared annotation RData files (exon_anno.RData, proseq.RData, procodingseq.RData)
//  * 3. [Input & Preparation] Read the PSM table
//  * 4. [Core Analysis] Convert the PSM table to SAM format using PSMtab2SAM
//  * 5. [Visualization & Output] Write the SAM file to disk

nextflow.enable.dsl = 2

process BIOC_PROBAMR_PROBAM_GENERATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

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
    .bm_deps <- c("proBAMr")
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
        library(proBAMr)
        
        # Define input file paths from the working directory
        gtfFile <- "test.gtf"
        CDSfasta <- "coding_seq.fasta"
        pepfasta <- "pro_seq.fasta"
        psmFile <- "passedPSM.tab"
        
        # Verify that input files exist
        for (f in c(gtfFile, CDSfasta, pepfasta, psmFile)) {
          if (!file.exists(f)) {
            stop(paste("Required input file missing:", f))
          }
        }
        
        # Define and create the annotation output directory
        annotation_path <- "annotation_output"
        if (!dir.exists(annotation_path)) {
          dir.create(annotation_path, recursive = TRUE)
        }
        
        # Stage 1: Prepare annotation files from GENCODE GTF and FASTA files
        PrepareAnnotationGENCODE(gtfFile, CDSfasta, pepfasta, 
                                 annotation_path, dbsnp=NULL, 
                                 splice_matrix=FALSE, COSMIC=FALSE)
        
        # Stage 2: Load the prepared annotation RData files
        load(file.path(annotation_path, "exon_anno.RData"))
        load(file.path(annotation_path, "proseq.RData"))
        load(file.path(annotation_path, "procodingseq.RData"))
        
        # Stage 3: Read the PSM table
        options(stringsAsFactors=FALSE)
        passedPSM <- read.table(psmFile, sep='\t', header=TRUE)
        
        # Stage 4: Convert the PSM table to SAM format using PSMtab2SAM
        SAM <- PSMtab2SAM(passedPSM, XScolumn='mvh', exon, proteinseq, 
                          procodingseq)
        
        # Stage 5: Write the SAM file to disk
        write.table(SAM, file='test.sam', 
                    sep='\t', quote=FALSE, row.names=FALSE, col.names=FALSE)
        
        # Save meaningful results as RDS for downstream analysis
        saveRDS(SAM, file="SAM_output.rds")

    writeLines(c(
        '"BIOC_PROBAMR_PROBAM_GENERATION":',
        paste0('    proBAMr: ', as.character(packageVersion('proBAMr')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_probam_generation.csv versions.yml
    """
}

workflow BIOC_PROBAMR_PROBAM_GENERATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ test.gtf, coding_seq.fasta, pro_seq.fasta, passedPSM.tab ] ]

    main:
    BIOC_PROBAMR_PROBAM_GENERATION(ch_input)

    emit:
    tables   = BIOC_PROBAMR_PROBAM_GENERATION.out.tables
    plots    = BIOC_PROBAMR_PROBAM_GENERATION.out.plots
    objects  = BIOC_PROBAMR_PROBAM_GENERATION.out.objects
    versions = BIOC_PROBAMR_PROBAM_GENERATION.out.versions
}
