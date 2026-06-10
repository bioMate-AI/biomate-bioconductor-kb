#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: proteodisco — genomic_variants_workflow
// Generate a customized protein database incorporating genomic variants (SNVs, MNVs, InDels) from VCF/MAF files.
// Input: validationSet_hg19.vcf
// Container: quay.io/biocontainers/bioconductor-proteodisco:1.16.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PROTEODISCO_GENOMIC_VARIANTS_WORKFLOW {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-proteodisco:1.16.0--r45hdfd78af_0"

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
    .bm_deps <- c("AnnotationDbi", "BSgenome.Hsapiens.UCSC.hg19", "TxDb.Hsapiens.UCSC.hg19.knownGene", "dplyr", "ggplot2", "knitr", "org.Hs.eg.db", "plyr", "proteodisco", "reshape2")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(ProteoDisco)
    library(TxDb.Hsapiens.UCSC.hg19.knownGene)
    library(BSgenome.Hsapiens.UCSC.hg19)
    library(ggplot2)
    library(reshape2)
    library(dplyr)
    library(org.Hs.eg.db)
    library(AnnotationDbi)
    
    # Define input file
    vcf_file <- "validationSet_hg19.vcf"
    
    # Check if input file exists in the working directory
    if (!file.exists(vcf_file)) {
      stop(paste("Required input file missing:", vcf_file, "\nPlease place it in the working directory."))
    }
    
    # 1. Generate the ProteoDiscography reference database
    message("Generating ProteoDiscography reference database...")
    ProteoDiscography.hg19 <- ProteoDisco::generateProteoDiscography(
      TxDb = TxDb.Hsapiens.UCSC.hg19.knownGene::TxDb.Hsapiens.UCSC.hg19.knownGene, 
      genomeSeqs = BSgenome.Hsapiens.UCSC.hg19::BSgenome.Hsapiens.UCSC.hg19
    )
    
    # 2. Import genomic variants
    message("Importing genomic variants from VCF...")
    ProteoDiscography.hg19 <- ProteoDisco::importGenomicVariants(
      ProteoDiscography = ProteoDiscography.hg19,
      files = vcf_file, 
      samplenames = 'Validation Set (GRCh37)',
      threads = 1, 
      performAnchorCheck = FALSE
    )
    
    # Generate and save summary of imported variants
    message("Generating variant summary...")
    z <- summary(ProteoDiscography.hg19, verbose = FALSE)
    
    # Save summary tables to CSV
    if (!is.null(z\$overviewMutations)) {
      write.csv(z\$overviewMutations, "imported_variants_overview.csv", row.names = FALSE)
      
      # Generate and save plot
      tryCatch({
        plot_data <- reshape2::melt(z\$overviewMutations, id.vars = 'sample') %>% 
          dplyr::filter(!is.na(value))
        
        p <- ggplot2::ggplot(plot_data, ggplot2::aes(x = sample, y = value, fill = variable)) + 
          ggplot2::geom_bar(stat = 'identity', width = .8, color = 'black', position = ggplot2::position_dodge(preserve = 'single')) + 
          ggplot2::scale_y_continuous(trans = scales::pseudo_log_trans(), breaks = c(0, 10, 100, 1000, 10000)) +
          ggplot2::labs(x = 'Provided samples', y = 'Nr. of variants (log10)', title = "Imported Genomic Variants Overview") +
          ggplot2::scale_fill_brewer(name = 'Category', palette = 'Greens') +
          ggplot2::theme_minimal()
        
        ggplot2::ggsave("variant_distribution.pdf", plot = p, width = 8, height = 6)
      }, error = function(e) {
        warning("Could not generate summary plot: ", e\$message)
      })
    }
    
    # 3. Incorporate genomic variants into transcripts
    message("Incorporating genomic variants into transcripts...")
    ProteoDiscography.hg19 <- ProteoDisco::incorporateGenomicVariants(
      ProteoDiscography = ProteoDiscography.hg19,
      aggregateSamples = FALSE, 
      aggregateWithinExon = TRUE, 
      aggregateWithinTranscript = TRUE, 
      ignoreOverlappingMutations = TRUE, 
      threads = 1
    )
    
    # Convert TxIDs to gene symbols to enrich the output
    message("Converting TxIDs to gene symbols...")
    tryCatch({
      x <- ProteoDisco::mutantTranscripts(ProteoDiscography.hg19)
      if (!is.null(x\$genomicVariants) && nrow(x\$genomicVariants) > 0) {
        geneSymbols <- unique(AnnotationDbi::select(
          org.Hs.eg.db::org.Hs.eg.db, 
          keys = x\$genomicVariants\$geneID, 
          keytype = 'ENTREZID', 
          columns = 'SYMBOL'
        ))
        
        x\$genomicVariants <- merge(
          x\$genomicVariants, geneSymbols, 
          by.x = 'geneID', by.y = 'ENTREZID', all.x = TRUE
        )
        
        ProteoDiscography.hg19 <- ProteoDisco::setMutantTranscripts(
          ProteoDiscography.hg19, 
          transcripts = x\$genomicVariants, 
          slotType = 'genomicVariants'
        )
        
        # Save mutant transcripts table
        write.csv(x\$genomicVariants, "mutant_transcripts_annotated.csv", row.names = FALSE)
      }
    }, error = function(e) {
      warning("Could not convert TxIDs to gene symbols: ", e\$message)
    })
    
    # 4. Export the customized database to FASTA
    message("Exporting customized protein database to FASTA...")
    ProteoDisco::exportProteoDiscography(
      ProteoDiscography = ProteoDiscography.hg19,
      outFile = 'example.fasta',
      aggregateSamples = TRUE
    )
    
    # Save the final ProteoDiscography object as RDS
    message("Saving ProteoDiscography object to RDS...")
    saveRDS(ProteoDiscography.hg19, file = "ProteoDiscography_hg19.rds")
    
    message("Pipeline completed successfully!")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_PROTEODISCO_GENOMIC_VARIANTS_WORKFLOW":
        proteodisco: \$(Rscript -e 'cat(as.character(packageVersion("proteodisco")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_genomic_variants_workflow.csv versions.yml
    """
}

workflow BIOC_PROTEODISCO_GENOMIC_VARIANTS_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ validationSet_hg19.vcf ] ]

    main:
    BIOC_PROTEODISCO_GENOMIC_VARIANTS_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_PROTEODISCO_GENOMIC_VARIANTS_WORKFLOW.out.tables
    plots    = BIOC_PROTEODISCO_GENOMIC_VARIANTS_WORKFLOW.out.plots
    objects  = BIOC_PROTEODISCO_GENOMIC_VARIANTS_WORKFLOW.out.objects
    versions = BIOC_PROTEODISCO_GENOMIC_VARIANTS_WORKFLOW.out.versions
}
