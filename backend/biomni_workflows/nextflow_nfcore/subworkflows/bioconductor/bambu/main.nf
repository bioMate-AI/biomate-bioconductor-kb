#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: bambu — transcript_discovery_and_quantification
// Perform transcript discovery and expression quantification from long-read RNA-Seq alignments and reference annotations, then export and visualize the results.
// Input: test.bam, Homo_sapiens.GRCh38.91_chr9_1_1000000.gtf, Homo_sapiens.GRCh38.dna_sm.primary_assembly_chr9_1_1000000.fa
// Container: quay.io/biocontainers/bioconductor-bambu:3.12.1--r45ha27e39d_1
// R packages: bambu, BiocFileCache, DESeq2, DEXSeq, ExperimentHub, nanoporernaseq
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BAMBU_TRANSCRIPT_DISCOVERY_AND_QUANTIFICATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-bambu:3.12.1--r45ha27e39d_1"

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
    .bm_deps <- c("bambu", "BiocFileCache", "DESeq2", "DEXSeq", "ExperimentHub", "nanoporernaseq", "SummarizedExperiment")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
    }

    # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
    for (.bm_d in list.files(".", full.names = TRUE)) {
      if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
        for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
          if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
        }
      }
    }
    
    # Load required library
    library(SummarizedExperiment)
    library(bambu)
    
    # Define input files from the working directory as specified by the user
    test.bam <- "test.bam"
    gtf.file <- "Homo_sapiens.GRCh38.91_chr9_1_1000000.gtf"
    fa.file <- "Homo_sapiens.GRCh38.dna_sm.primary_assembly_chr9_1_1000000.fa"
    
    # --- Prepare reference annotations ---
    bambuAnnotations <- prepareAnnotations(gtf.file)
    
    # --- Run bambu to perform transcript discovery and ---
    se <- bambu(reads = test.bam, annotations = bambuAnnotations, genome = fa.file)
    
    # Set up variables for the multi-sample documented steps using our input data
    bamFiles <- test.bam
    HsChr22BambuAnnotation <- bambuAnnotations
    genomeSequence <- fa.file
    
    # Run bambu for the multi-sample workflow
    se.multiSample <- bambu(reads = bamFiles, annotations = HsChr22BambuAnnotation, genome = genomeSequence)
    
    # --- Convert transcript expression estimates to gene ---
    seGene.multiSample <- transcriptToGeneExpression(se.multiSample)
    
    # --- Export the extended annotations and expression estimates ---
    save.dir <- "bambu_outputs"
    if (!dir.exists(save.dir)) {
        dir.create(save.dir, recursive = TRUE)
    }
    writeBambuOutput(se.multiSample, path = save.dir, prefix = "NanoporeRNASeq_")
    
    save.file <- "extended_annotations.gtf"
    writeToGTF(rowRanges(se.multiSample), file = save.file)
    
    # Save RDS objects of the results for downstream analysis
    saveRDS(se.multiSample, file = file.path(save.dir, "se_multiSample.rds"))
    saveRDS(seGene.multiSample, file = file.path(save.dir, "seGene_multiSample.rds"))
    
    # --- Visualize sample correlations and annotations ---
    # We write the plots to a PDF file and wrap them in tryCatch blocks to ensure
    # robustness (e.g., if single-sample limits PCA/heatmap or if the specific gene is absent)
    pdf("bambu_visualizations.pdf", width = 8, height = 8)
    
    tryCatch({
        plotBambu(se.multiSample, type = "heatmap")
    }, error = function(e) {
        message("Could not generate heatmap plot: ", e\$message)
    })
    
    tryCatch({
        plotBambu(se.multiSample, type = "pca")
    }, error = function(e) {
        message("Could not generate PCA plot: ", e\$message)
    })
    
    tryCatch({
        plotBambu(se.multiSample, type = "annotation", gene_id = "ENSG00000099968")
    }, error = function(e) {
        message("Could not plot annotation for ENSG00000099968: ", e\$message)
        # Fallback: attempt to plot the first available gene ID from the results
        genes <- unique(as.character(rowData(se.multiSample)\$GENEID))
        if (length(genes) > 0) {
            fallback_gene <- genes[1]
            message("Attempting fallback plot with available gene_id: ", fallback_gene)
            try(plotBambu(se.multiSample, type = "annotation", gene_id = fallback_gene))
        }
    })
    
    dev.off()

    writeLines(c(
        '"BIOC_BAMBU_TRANSCRIPT_DISCOVERY_AND_QUANTIFICATION":',
        paste0('        bambu: ', as.character(packageVersion("bambu")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_transcript_discovery_and_quantification.csv versions.yml
    """
}

workflow BIOC_BAMBU_TRANSCRIPT_DISCOVERY_AND_QUANTIFICATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ test.bam, Homo_sapiens.GRCh38.91_chr9_1_1000000.gtf, Homo_sapiens.GRCh38.dna_sm.primary_assembly_chr9_1_1000000.fa ] ]

    main:
    BIOC_BAMBU_TRANSCRIPT_DISCOVERY_AND_QUANTIFICATION(ch_input)

    emit:
    tables   = BIOC_BAMBU_TRANSCRIPT_DISCOVERY_AND_QUANTIFICATION.out.tables
    plots    = BIOC_BAMBU_TRANSCRIPT_DISCOVERY_AND_QUANTIFICATION.out.plots
    objects  = BIOC_BAMBU_TRANSCRIPT_DISCOVERY_AND_QUANTIFICATION.out.objects
    versions = BIOC_BAMBU_TRANSCRIPT_DISCOVERY_AND_QUANTIFICATION.out.versions
}
