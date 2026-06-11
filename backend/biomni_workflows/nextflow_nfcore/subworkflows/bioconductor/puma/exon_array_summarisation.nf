#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: puma — exon_array_summarisation
// Calculate gene and transcript expression levels and standard errors from Affymetrix exon arrays.
// Input: exonFilenames, SampleNameTable
// Container: quay.io/biocontainers/bioconductor-puma:3.52.0--r45h01b2380_0
// R packages: oligo, puma, pumadata
// Bioconductor: 3.20 | R: 4.4
// Requires: oligo, puma, pumadata
// Visualizations: box plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read CEL files using oligo
//  * 2. [Visualization & Output] Summarise to gene and transcript levels using gmoExon or igmoExon
//  * 3. [Core Analysis] Extract expression and standard error values
//  * 4. [Visualization & Output] Export results using write.reslts

nextflow.enable.dsl = 2

process BIOC_PUMA_EXON_ARRAY_SUMMARISATION {
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
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("oligo", "puma", "pumadata")
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
    library(puma)
    library(oligo)
    library(pumadata)
    
    # 1. Read CEL files from the working directory
    exonFilenames <- list.files(pattern = "\\\\.[Cc][Ee][Ll]\$")
    if (length(exonFilenames) == 0) {
      stop("No CEL files found in the working directory.")
    }
    
    # Look for any file containing "SampleNameTable" in its name
    possible_tables <- list.files(pattern = "SampleNameTable")
    if (length(possible_tables) > 0) {
      sample_table_file <- possible_tables[1]
    } else {
      stop("SampleNameTable file not found in the working directory.")
    }
    
    # 2. Summarise to gene and transcript levels using gmoExon
    oligo.exon <- read.celfiles(exonFilenames)
    eset_gmoExon <- gmoExon(oligo.exon, exontype="Human", gsnorm="none")
    
    # 3. Extract expression and standard error values
    print("gmoExon Gene Expression (First Row):")
    print(exprs(eset_gmoExon\$gene)[1,])
    print("gmoExon Gene SE (First Row):")
    print(assayDataElement(eset_gmoExon\$gene, "se.exprs")[1,])
    
    print("gmoExon Transcript Expression (First Row):")
    print(exprs(eset_gmoExon\$transcript)[1,])
    print("gmoExon Transcript SE (First Row):")
    print(assayDataElement(eset_gmoExon\$transcript, "se.exprs")[1,])
    
    # 4. Export results using write.reslts
    write.reslts(eset_gmoExon\$gene, file="eset_gmoExon_gene")
    write.reslts(eset_gmoExon\$transcript, file="eset_gmoExon_transcript")
    
    # 5. Summarise using igmoExon
    cel.path <- "."
    eset_igmoExon <- igmoExon(cel.path=cel.path, SampleNameTable=sample_table_file
                             , exontype="Human"
                             , gsnorm="none", condition="Yes")
    
    # Extract and print igmoExon values
    print("igmoExon Gene Expression (First Row):")
    print(exprs(eset_igmoExon\$gene)[1,])
    print("igmoExon Gene SE (First Row):")
    print(assayDataElement(eset_igmoExon\$gene, "se.exprs")[1,])
    
    print("igmoExon Transcript Expression (First Row):")
    print(exprs(eset_igmoExon\$transcript)[1,])
    print("igmoExon Transcript SE (First Row):")
    print(assayDataElement(eset_igmoExon\$transcript, "se.exprs")[1,])
    
    # Export igmoExon results
    write.reslts(eset_igmoExon\$gene, file="eset_igmoExon_gene")
    write.reslts(eset_igmoExon\$transcript, file="eset_igmoExon_transcript")
    
    # Save RDS objects
    saveRDS(eset_gmoExon, "eset_gmoExon.rds")
    saveRDS(eset_igmoExon, "eset_igmoExon.rds")
    
    # Generate diagnostic plots
    pdf("exon_array_summarisation_plots.pdf", width=10, height=8)
    par(mfrow=c(2,2))
    boxplot(exprs(eset_gmoExon\$gene), main="gmoExon Gene Expression", col="lightblue", las=2)
    boxplot(exprs(eset_gmoExon\$transcript), main="gmoExon Transcript Expression", col="lightgreen", las=2)
    boxplot(exprs(eset_igmoExon\$gene), main="igmoExon Gene Expression", col="lightpink", las=2)
    boxplot(exprs(eset_igmoExon\$transcript), main="igmoExon Transcript Expression", col="lightyellow", las=2)
    dev.off()
    
    message("Pipeline completed successfully. Outputs written to working directory.")

    writeLines(c(
        '"BIOC_PUMA_EXON_ARRAY_SUMMARISATION":',
        paste0('    puma: ', as.character(packageVersion('puma')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_exon_array_summarisation.csv versions.yml
    """
}

workflow BIOC_PUMA_EXON_ARRAY_SUMMARISATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ exonFilenames, SampleNameTable ] ]

    main:
    BIOC_PUMA_EXON_ARRAY_SUMMARISATION(ch_input)

    emit:
    tables   = BIOC_PUMA_EXON_ARRAY_SUMMARISATION.out.tables
    plots    = BIOC_PUMA_EXON_ARRAY_SUMMARISATION.out.plots
    objects  = BIOC_PUMA_EXON_ARRAY_SUMMARISATION.out.objects
    versions = BIOC_PUMA_EXON_ARRAY_SUMMARISATION.out.versions
}
