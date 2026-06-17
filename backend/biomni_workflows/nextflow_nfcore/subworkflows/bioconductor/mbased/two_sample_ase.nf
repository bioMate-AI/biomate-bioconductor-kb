#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MBASED — two_sample_ase
// Compare allele-specific gene expression (ASE) between two samples (e.g., tumor and normal) to detect differences in major allele frequency.
// Input: snv_coordinates.bed, rna_seq_counts_two_samples.tsv
// Container: quay.io/biocontainers/bioconductor-mbased:1.44.0--r45hdfd78af_0
// R packages: BiocParallel, MBASED, SummarizedExperiment
// Bioconductor: 3.20 | R: 4.4
// Requires: BiocParallel, MBASED, SummarizedExperiment
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define SNV coordinates and gene assignments using GRanges
//  * 2. [Visualization & Output] Construct a SummarizedExperiment with multi-column allele count assays
//  * 3. [Core Analysis] Run runMBASED to calculate comparative ASE statistics
//  * 4. [Visualization & Output] Extract and summarize the results

nextflow.enable.dsl = 2

process BIOC_MBASED_TWO_SAMPLE_ASE {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("BiocParallel", "MBASED", "SummarizedExperiment")
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
    library(MBASED)
    library(SummarizedExperiment)
    library(BiocParallel)
    
    # Set seed for reproducibility
    set.seed(988482)
    
    # 1. Read SNV coordinates and construct GRanges
    # Expecting columns: chrom, start, end, name, aseID, allele1, allele2
    first_line <- readLines("snv_coordinates.bed", n=1)
    has_header <- grepl("chrom|start|end|aseID", first_line, ignore.case=TRUE)
    snvs_df <- read.table("snv_coordinates.bed", header=has_header, sep="\t", stringsAsFactors=FALSE)
    if (!has_header) {
      colnames(snvs_df)[1:7] <- c("chrom", "start", "end", "name", "aseID", "allele1", "allele2")
    }
    
    mySNVs_2s <- GRanges(
      seqnames=snvs_df\$chrom,
      ranges=IRanges(start=snvs_df\$start, end=snvs_df\$end),
      aseID=snvs_df\$aseID,
      allele1=snvs_df\$allele1,
      allele2=snvs_df\$allele2
    )
    names(mySNVs_2s) <- snvs_df\$name
    
    # 2. Read RNA-seq counts and construct SummarizedExperiment
    # Expecting columns: snv_id, tumor_allele1, tumor_allele2, normal_allele1, normal_allele2
    counts_df <- read.table("rna_seq_counts_two_samples.tsv", header=TRUE, sep="\t", stringsAsFactors=FALSE)
    rownames(counts_df) <- counts_df\$snv_id
    counts_df <- counts_df[names(mySNVs_2s), ]
    
    myTumorNormalExample <- SummarizedExperiment(
      assays=list(
        lociAllele1Counts=matrix(
          c(counts_df\$tumor_allele1, counts_df\$normal_allele1),
          ncol=2,
          dimnames=list(
           names(mySNVs_2s), 
           c('tumor', 'normal')
          )
        ),
        lociAllele2Counts=matrix(
          c(counts_df\$tumor_allele2, counts_df\$normal_allele2),
          ncol=2, 
          dimnames=list(
           names(mySNVs_2s), 
           c('tumor', 'normal')
          )
        )
      ),
      rowRanges=mySNVs_2s
    )
    
    # 3. Run runMBASED to calculate comparative ASE statistics
    ASEresults_2s <- runMBASED(
      ASESummarizedExperiment=myTumorNormalExample,
      isPhased=FALSE,
      numSim=10^6,
      BPPARAM = SerialParam()
    )
    
    # 4. Extract and summarize the results
    class(ASEresults_2s)
    names(assays(ASEresults_2s))
    assays(ASEresults_2s)\$majorAlleleFrequencyDifference
    assays(ASEresults_2s)\$pValueASE
    assays(ASEresults_2s)\$pValueHeterogeneity
    rowRanges(ASEresults_2s)
    names(metadata(ASEresults_2s))
    class(metadata(ASEresults_2s)\$locusSpecificResults)
    names(assays(metadata(ASEresults_2s)\$locusSpecificResults))
    assays(metadata(ASEresults_2s)\$locusSpecificResults)\$allele1IsMajor
    assays(metadata(ASEresults_2s)\$locusSpecificResults)\$MAFDifference
    rowRanges(metadata(ASEresults_2s)\$locusSpecificResults)
    
    # Define function to print out the summary of ASE results
    summarizeASEResults_2s <- function(MBASEDOutput) {
      geneOutputDF <- data.frame(
       majorAlleleFrequencyDifference=assays(MBASEDOutput)\$majorAlleleFrequencyDifference[,1],
       pValueASE=assays(MBASEDOutput)\$pValueASE[,1],  
       pValueHeterogeneity=assays(MBASEDOutput)\$pValueHeterogeneity[,1]
      )   
      lociOutputGR <- rowRanges(metadata(MBASEDOutput)\$locusSpecificResults)
      lociOutputGR\$allele1IsMajor <- assays(metadata(MBASEDOutput)\$locusSpecificResults)\$allele1IsMajor[,1]
      lociOutputGR\$MAFDifference <- assays(metadata(MBASEDOutput)\$locusSpecificResults)\$MAFDifference[,1]
      lociOutputList <- split(lociOutputGR, factor(lociOutputGR\$aseID, levels=unique(lociOutputGR\$aseID))) 
      return(
       list(
         geneOutput=geneOutputDF,
         locusOutput=lociOutputList
       )
      )
    }
    
    results_summary <- summarizeASEResults_2s(ASEresults_2s)
    
    # Write outputs to files
    write.csv(results_summary\$geneOutput, "gene_level_ase_results.csv", row.names=TRUE)
    locus_df <- as.data.frame(unlist(results_summary\$locusOutput))
    write.csv(locus_df, "locus_level_ase_results.csv", row.names=TRUE)
    saveRDS(ASEresults_2s, "MBASED_results.rds")

    writeLines(c(
        '"BIOC_MBASED_TWO_SAMPLE_ASE":',
        paste0('    MBASED: ', as.character(packageVersion('MBASED')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_two_sample_ase.csv versions.yml
    """
}

workflow BIOC_MBASED_TWO_SAMPLE_ASE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ snv_coordinates.bed, rna_seq_counts_two_samples.tsv ] ]

    main:
    BIOC_MBASED_TWO_SAMPLE_ASE(ch_input)

    emit:
    tables   = BIOC_MBASED_TWO_SAMPLE_ASE.out.tables
    plots    = BIOC_MBASED_TWO_SAMPLE_ASE.out.plots
    objects  = BIOC_MBASED_TWO_SAMPLE_ASE.out.objects
    versions = BIOC_MBASED_TWO_SAMPLE_ASE.out.versions
}
