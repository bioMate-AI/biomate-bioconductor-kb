#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: nearBynding — nearbynding_rna_structure_pipeline
// Map and analyze RNA secondary structure contexts proximal to protein-binding sites using CLIP-seq data and CapR/StereoGene.
// Input: transcript_list.Rda, genome.gtf, genome.fa, protein_binding.bam
// Container: quay.io/biocontainers/bioconductor-nearbynding:1.16.0--r44hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Rsamtools, nearBynding
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Load user input transcript list
//  * 2. [Visualization & Output] Get chromosome sizes for the concatenated transcriptome
//  * 3. [Visualization & Output] Extract transcriptome sequences
//  * 4. [Visualization & Output] Fold RNA sequences using CapR
//  * 5. [Visualization & Output] Convert and clean BAM files to bedGraph (or handle BED
//  * 6. [Visualization & Output] Map protein binding data to the concatenated transcriptome
//  * 7. [Visualization & Output] Process CapR output and map RNA structures to the
//  * 8. [Visualization & Output] Calculate cross-correlation between RNA structure and
//  * 9. [Visualization & Output] Visualize cross-correlation results
//  * 10. [Visualization & Output] Calculate Wasserstein distance between different

nextflow.enable.dsl = 2

process BIOC_NEARBYNDING_NEARBYNDING_RNA_STRUCTURE_PIPELINE {
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
    .bm_deps <- c("nearBynding", "Rsamtools")
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
        library(nearBynding)
        library(Rsamtools)
        
        # --- Load user input transcript list ---
        load("transcript_list.Rda")
        
        # Define input file paths
        gtf <- "genome.gtf"
        ref_genome <- "genome.fa"
        
        # Generate a chain file mapping transcript regions end-to-end
        GenomeMappingToChainFile(genome_gtf = gtf,
                                 out_chain_name = "test.chain",
                                 RNA_fragment = "three_prime_utr",
                                 transcript_list = transcript_list,
                                 alignment = "hg38")
        
        # --- Get chromosome sizes for the concatenated transcriptome ---
        getChainChrSize(chain = "test.chain", 
                        out_chr = "user_transcriptome.size")
        
        # --- Extract transcriptome sequences ---
        ExtractTranscriptomeSequence(transcript_list = transcript_list,
                                     ref_genome = ref_genome,
                                     genome_gtf = gtf,
                                     RNA_fragment = "three_prime_utr",
                                     exome_prefix = "user_transcriptome")
        
        # --- Fold RNA sequences using CapR ---
        user_transcriptome.fa <- "user_transcriptome.fa"
        runCapR(in_file = user_transcriptome.fa)
        
        # --- Convert and clean BAM files to bedGraph (or handle BED ---
        if (file.exists("protein_binding.bam")) {
          sorted_bam <- sortBam("protein_binding.bam", "protein_sorted")
          CleanBAMtoBG(in_bam = sorted_bam)
          protein_input <- "protein_sorted.bedGraph"
          is_bed <- FALSE
        } else if (file.exists("protein_binding.bed")) {
          protein_input <- "protein_binding.bed"
          is_bed <- TRUE
        } else {
          stop("Error: Neither protein_binding.bam nor protein_binding.bed was found in the working directory.")
        }
        
        # --- Map protein binding data to the concatenated transcriptome ---
        if (is_bed) {
          liftOverToExomicBG(input = protein_input,
                             chain = "test.chain",
                             chrom_size = "user_transcriptome.size",
                             output_bg = "protein_liftOver.bedGraph",
                             format = "BED")
        } else {
          liftOverToExomicBG(input = protein_input,
                             chain = "test.chain",
                             chrom_size = "user_transcriptome.size",
                             output_bg = "protein_liftOver.bedGraph")
        }
        
        # --- Process CapR output and map RNA structures to the ---
        processCapRout(CapR_outfile = "user_transcriptome.out",
                       chain = "test.chain",
                       output_prefix = "user_transcriptome",
                       chrom_size = "user_transcriptome.size",
                       genome_gtf = gtf,
                       RNA_fragment = "three_prime_utr")
        
        # --- Calculate cross-correlation between RNA structure and ---
        runStereogeneOnCapR(protein_file = "protein_liftOver.bedGraph",
                            chrom_size = "user_transcriptome.size",
                            name_config = "user_transcriptome.cfg",
                            input_prefix = "user_transcriptome")
        
        runStereogene(track_files = c("user_transcriptome_stem_liftOver.bedGraph",
                                      "protein_liftOver.bedGraph"),
                      name_config = "user_transcriptome.cfg")
        
        # --- Visualize cross-correlation results ---
        visualizeCapRStereogene(CapR_prefix = "user_transcriptome",
                                protein_file = "protein_liftOver",
                                heatmap = TRUE,
                                out_file = "all_contexts_heatmap",
                                x_lim = c(-500, 500))
        
        visualizeCapRStereogene(CapR_prefix = "user_transcriptome",
                                protein_file = "protein_liftOver",
                                x_lim = c(-500, 500),
                                out_file = "all_contexts_line")
        
        visualizeStereogene(context_file = "user_transcriptome_stem_liftOver",
                            protein_file = "protein_liftOver",
                            out_file = "stem_line",
                            x_lim = c(-500, 500))
        
        visualizeStereogene(context_file = "user_transcriptome_stem_liftOver",
                            protein_file = "protein_liftOver",
                            heatmap = TRUE,
                            out_file = "stem_heatmap",
                            x_lim = c(-500, 500))
        
        # --- Calculate Wasserstein distance between different ---
        dist_stem_hairpin <- bindingContextDistance(RNA_context = "user_transcriptome_stem_liftOver",
                                                    protein_file = "protein_liftOver",
                                                    RNA_context_2 = "user_transcriptome_hairpin_liftOver")
        
        # Save distance results to an RDS file
        saveRDS(dist_stem_hairpin, file = "binding_context_distance_stem_hairpin.rds")

    writeLines(c(
        '"BIOC_NEARBYNDING_NEARBYNDING_RNA_STRUCTURE_PIPELINE":',
        paste0('    nearBynding: ', as.character(packageVersion('nearBynding')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_nearbynding_rna_structure_pipeline.csv versions.yml
    """
}

workflow BIOC_NEARBYNDING_NEARBYNDING_RNA_STRUCTURE_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ transcript_list.Rda, genome.gtf, genome.fa, protein_binding.bam ] ]

    main:
    BIOC_NEARBYNDING_NEARBYNDING_RNA_STRUCTURE_PIPELINE(ch_input)

    emit:
    tables   = BIOC_NEARBYNDING_NEARBYNDING_RNA_STRUCTURE_PIPELINE.out.tables
    plots    = BIOC_NEARBYNDING_NEARBYNDING_RNA_STRUCTURE_PIPELINE.out.plots
    objects  = BIOC_NEARBYNDING_NEARBYNDING_RNA_STRUCTURE_PIPELINE.out.objects
    versions = BIOC_NEARBYNDING_NEARBYNDING_RNA_STRUCTURE_PIPELINE.out.versions
}
