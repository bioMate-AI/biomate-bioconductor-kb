#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GenomicDistributions — custom_reference_generation
// Generate custom reference data (chromosome sizes, TSSs, and gene models) from FASTA and GTF files for non-standard genomes.
// Input: genome.fa.gz, annotation.gtf.gz
// Container: quay.io/biocontainers/bioconductor-genomicdistributions:1.18.0--r45hdfd78af_0
// Requires: GenomicDistributions
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Extract chromosome sizes from FASTA using getChromSizesFromFasta
//  * 2. [Core Analysis] Generate equally sized genome bins using getGenomeBins
//  * 3. [Core Analysis] Extract transcription start sites (TSS) from GTF using getTssFromGTF
//  * 4. [Core Analysis] Extract gene models from GTF using getGeneModelsFromGTF
//  * 5. [Input & Preparation] Create a list of genomic partitions using genomePartitionList

nextflow.enable.dsl = 2

process BIOC_GENOMICDISTRIBUTIONS_CUSTOM_REFERENCE_GENERATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

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
    .bm_deps <- c("GenomicDistributions")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
    
    # Load required libraries
    library(GenomicDistributions)
    
    # Define input files from the working directory
    fastaSource = "genome.fa.gz"
    gtfSource = "annotation.gtf.gz"
    
    # Verify that the required user input files exist
    if (!file.exists(fastaSource)) {
      stop(paste("Error: Required input FASTA file missing:", fastaSource))
    }
    if (!file.exists(gtfSource)) {
      stop(paste("Error: Required input GTF file missing:", gtfSource))
    }
    
    # Stage 1: Extract chromosome sizes from FASTA
    message("Stage 1: Extracting chromosome sizes from FASTA...")
    CEelegansChromSizes = getChromSizesFromFasta(source=fastaSource)
    
    # Stage 2: Generate equally sized genome bins
    message("Stage 2: Generating genome bins...")
    bins = getGenomeBins(CEelegansChromSizes)
    
    # Stage 3: Extract transcription start sites (TSS) from GTF
    message("Stage 3: Extracting TSSs from GTF...")
    CEelegansTSSs = getTssFromGTF(source=gtfSource, convertEnsemblUCSC=TRUE)
    
    # Stage 4: Extract gene models from GTF
    message("Stage 4: Extracting gene models from GTF...")
    features = c("gene", "exon", "three_prime_utr", "five_prime_utr")
    CEelegansGeneModels = getGeneModelsFromGTF(source=gtfSource, features=features, convertEnsemblUCSC=TRUE)
    
    # Stage 5: Create a list of genomic partitions
    message("Stage 5: Creating genomic partition list...")
    partitionList = genomePartitionList(CEelegansGeneModels\$gene, CEelegansGeneModels\$exon, CEelegansGeneModels\$three_prime_utr, CEelegansGeneModels\$five_prime_utr)
    
    # Save meaningful results to output files
    message("Saving results to output files...")
    
    # Save chromosome sizes
    saveRDS(CEelegansChromSizes, file = "chrom_sizes.rds")
    write.csv(as.data.frame(CEelegansChromSizes), file = "chrom_sizes.csv", row.names = TRUE)
    
    # Save genome bins
    saveRDS(bins, file = "genome_bins.rds")
    
    # Save TSSs
    saveRDS(CEelegansTSSs, file = "tss.rds")
    
    # Save gene models
    saveRDS(CEelegansGeneModels, file = "gene_models.rds")
    
    # Save partition list
    saveRDS(partitionList, file = "partition_list.rds")
    
    message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_GENOMICDISTRIBUTIONS_CUSTOM_REFERENCE_GENERATION":',
        paste0('    GenomicDistributions: ', as.character(packageVersion('GenomicDistributions')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_custom_reference_generation.csv versions.yml
    """
}

workflow BIOC_GENOMICDISTRIBUTIONS_CUSTOM_REFERENCE_GENERATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ genome.fa.gz, annotation.gtf.gz ] ]

    main:
    BIOC_GENOMICDISTRIBUTIONS_CUSTOM_REFERENCE_GENERATION(ch_input)

    emit:
    tables   = BIOC_GENOMICDISTRIBUTIONS_CUSTOM_REFERENCE_GENERATION.out.tables
    plots    = BIOC_GENOMICDISTRIBUTIONS_CUSTOM_REFERENCE_GENERATION.out.plots
    objects  = BIOC_GENOMICDISTRIBUTIONS_CUSTOM_REFERENCE_GENERATION.out.objects
    versions = BIOC_GENOMICDISTRIBUTIONS_CUSTOM_REFERENCE_GENERATION.out.versions
}
