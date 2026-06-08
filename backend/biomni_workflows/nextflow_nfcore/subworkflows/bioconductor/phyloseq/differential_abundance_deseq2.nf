#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: phyloseq — differential_abundance_deseq2
// Perform differential abundance testing on microbiome count data using negative binomial models via DESeq2.
// Input: study_1457_split_library_seqs_and_mapping.zip
// Container: quay.io/biocontainers/bioconductor-phyloseq:1.54.0--r45hdfd78af_0
// Requires: DESeq2, ggplot2, phyloseq
// Visualizations: plot (ggplot/base)
// QC: dispersion/size-factor estimation
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Import OTU count data and sample metadata using microbio_me_qiime
//  * 2. [Core Analysis] Filter low-quality samples and missing metadata using subset_samples and prune_samples
//  * 3. [Core Analysis] Convert the phyloseq object to a DESeqDataSet using phyloseq_to_deseq2
//  * 4. [Core Analysis] Calculate geometric means and estimate size factors using estimateSizeFactors
//  * 5. [Core Analysis] Run differential abundance testing using DESeq
//  * 6. [Core Analysis] Extract and filter significant results using results
//  * 7. [Visualization & Output] Visualize log2 fold changes of significant taxa using ggplot

nextflow.enable.dsl = 2

process BIOC_PHYLOSEQ_DIFFERENTIAL_ABUNDANCE_DESEQ2 {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-metagenomics:3.20"

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
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
    
    # Load required libraries
    library("phyloseq")
    library("DESeq2")
    library("ggplot2")
    
    # 1. Import OTU count data and sample metadata using microbio_me_qiime
    # Read the user input file from the working directory
    filepath = "study_1457_split_library_seqs_and_mapping.zip"
    kostic = microbio_me_qiime(filepath)
    
    # Save the imported raw phyloseq object
    saveRDS(kostic, "kostic_raw.rds")
    
    # 2. Filter low-quality samples and missing metadata using subset_samples and prune_samples
    kostic <- subset_samples(kostic, DIAGNOSIS != "None")
    kostic <- prune_samples(sample_sums(kostic) > 500, kostic)
    
    # Save the filtered phyloseq object
    saveRDS(kostic, "kostic_filtered.rds")
    
    # 3. Convert the phyloseq object to a DESeqDataSet using phyloseq_to_deseq2
    diagdds = phyloseq_to_deseq2(kostic, ~ DIAGNOSIS)
    
    # 4. Calculate geometric means and estimate size factors using estimateSizeFactors
    gm_mean = function(x, na.rm=TRUE){ exp(sum(log(x[x > 0]), na.rm=na.rm) / length(x)) }
    geoMeans = apply(counts(diagdds), 1, gm_mean)
    diagdds = estimateSizeFactors(diagdds, geoMeans = geoMeans)
    
    # 5. Run differential abundance testing using DESeq
    diagdds = DESeq(diagdds, fitType="local")
    
    # Save the DESeqDataSet object
    saveRDS(diagdds, "diagdds_results.rds")
    
    # 6. Extract and filter significant results using results
    res = results(diagdds)
    res = res[order(res\$padj, na.last=NA), ]
    alpha = 0.01
    sigtab = res[(res\$padj < alpha), ]
    sigtab = cbind(as(sigtab, "data.frame"), as(tax_table(kostic)[rownames(sigtab), ], "matrix"))
    
    # Write the significant results table to a CSV file
    write.csv(sigtab, "significant_taxa_deseq2.csv", row.names = TRUE)
    
    # 7. Visualize log2 fold changes of significant taxa using ggplot
    theme_set(theme_bw())
    sigtabgen = subset(sigtab, !is.na(Genus))
    x = tapply(sigtabgen\$log2FoldChange, sigtabgen\$Phylum, function(x) max(x))
    x = sort(x, TRUE)
    sigtabgen\$Phylum = factor(as.character(sigtabgen\$Phylum), levels=names(x))
    x = tapply(sigtabgen\$log2FoldChange, sigtabgen\$Genus, function(x) max(x))
    x = sort(x, TRUE)
    sigtabgen\$Genus = factor(as.character(sigtabgen\$Genus), levels=names(x))
    
    # Generate the plot exactly as documented
    ggplot(sigtabgen, aes(y=Genus, x=log2FoldChange, color=Phylum)) + 
      geom_vline(xintercept = 0.0, color = "gray", size = 0.5) + 
      geom_point(size=6) + 
      theme(axis.text.x = element_text(angle = -90, hjust = 0, vjust=0.5))
    
    # Save the generated plot to a PDF file
    ggsave("differential_abundance_plot.pdf", width = 10, height = 8)

    writeLines(c(
        '"BIOC_PHYLOSEQ_DIFFERENTIAL_ABUNDANCE_DESEQ2":',
        paste0('    phyloseq: ', as.character(packageVersion('phyloseq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_differential_abundance_deseq2.csv versions.yml
    """
}

workflow BIOC_PHYLOSEQ_DIFFERENTIAL_ABUNDANCE_DESEQ2_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ study_1457_split_library_seqs_and_mapping.zip ] ]

    main:
    BIOC_PHYLOSEQ_DIFFERENTIAL_ABUNDANCE_DESEQ2(ch_input)

    emit:
    tables   = BIOC_PHYLOSEQ_DIFFERENTIAL_ABUNDANCE_DESEQ2.out.tables
    plots    = BIOC_PHYLOSEQ_DIFFERENTIAL_ABUNDANCE_DESEQ2.out.plots
    objects  = BIOC_PHYLOSEQ_DIFFERENTIAL_ABUNDANCE_DESEQ2.out.objects
    versions = BIOC_PHYLOSEQ_DIFFERENTIAL_ABUNDANCE_DESEQ2.out.versions
}
