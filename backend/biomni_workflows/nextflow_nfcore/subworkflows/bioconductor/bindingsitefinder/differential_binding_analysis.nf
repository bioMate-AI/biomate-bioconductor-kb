#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: BindingSiteFinder — differential_binding_analysis
// Compare RBP binding sites between two conditions (e.g., WT vs KO) while correcting for gene expression changes using a binding-bin vs background-bin approach.
// Input: wt_pureclip.bed, ko_pureclip.bed, wt_plus.bw, wt_minus.bw, ko_plus.bw, ko_minus.bw, gencode_v37_annotation.gff3
// Container: quay.io/biocontainers/bioconductor-bindingsitefinder:2.8.0--r45hdfd78af_0
// R packages: BindingSiteFinder, GenomicFeatures, rtracklayer, txdbmaker
// Bioconductor: 3.20 | R: 4.4
// Requires: BindingSiteFinder, GenomicFeatures, rtracklayer, txdbmaker
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define binding sites for each condition separately
//  * 2. [Core Analysis] Combine the datasets using the + operator
//  * 3. [Core Analysis] Calculate binding site and background counts per gene using calculateBsBackground
//  * 4. [Core Analysis] Filter out low-signal or imbalanced genes using filterBsBackground
//  * 5. [Core Analysis] Perform differential testing using calculateBsFoldChange
//  * 6. [Visualization & Output] Visualize results using plotBsMA or geneRegulationPlot

nextflow.enable.dsl = 2

process BIOC_BINDINGSITEFINDER_DIFFERENTIAL_BINDING_ANALYSIS {
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
    .bm_deps <- c("BindingSiteFinder", "GenomicFeatures", "rtracklayer", "txdbmaker")
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
        
        library(BindingSiteFinder)
        library(rtracklayer)
        library(GenomicFeatures)
        
        if (!requireNamespace("txdbmaker", quietly = TRUE)) {
          makeTxDbFromGFF_func = GenomicFeatures::makeTxDbFromGFF
        } else {
          library(txdbmaker)
          makeTxDbFromGFF_func = txdbmaker::makeTxDbFromGFF
        }
        
        # 1. Load Gene Annotations and Transcript Regions
        annoFile = "gencode_v37_annotation.gff3"
        annoDb = makeTxDbFromGFF_func(file = annoFile, format = "gff3")
        annoInfo = rtracklayer::import(annoFile, format = "gff3")
        
        gns = GenomicFeatures::genes(annoDb)
        idx = match(gns\$gene_id, annoInfo\$gene_id)
        meta_gns = cbind(elementMetadata(gns), elementMetadata(annoInfo)[idx,])
        meta_gns = meta_gns[, !duplicated(colnames(meta_gns))]
        elementMetadata(gns) = meta_gns
        
        cdseq = GenomicFeatures::cds(annoDb)
        intrns = unlist(GenomicFeatures::intronsByTranscript(annoDb))
        utrs3 = unlist(GenomicFeatures::threeUTRsByTranscript(annoDb))
        utrs5 = unlist(GenomicFeatures::fiveUTRsByTranscript(annoDb))
        regions = GRangesList(CDS = cdseq, Intron = intrns, UTR3 = utrs3, UTR5 = utrs5)
        
        # 2. Load Crosslink Sites and Coverage to Define Binding Sites for Each Condition
        cs.wt = rtracklayer::import(con = "wt_pureclip.bed", format = "BED")
        if (any(width(cs.wt) != 1)) {
          cs.wt = resize(cs.wt, width = 1, fix = "center")
        }
        
        meta.wt = data.frame(
          id = 1,
          condition = factor("WT"),
          clPlus = "wt_plus.bw",
          clMinus = "wt_minus.bw"
        )
        bds.wt.raw = BSFDataSetFromBigWig(ranges = cs.wt, meta = meta.wt, silent = TRUE)
        chrom.wt = as.character(seqnames(cs.wt)[1])
        bds.wt = BSFind(object = bds.wt.raw, anno.genes = gns, anno.transcriptRegionList = regions, est.subsetChromosome = chrom.wt, veryQuiet = TRUE)
        
        cs.ko = rtracklayer::import(con = "ko_pureclip.bed", format = "BED")
        if (any(width(cs.ko) != 1)) {
          cs.ko = resize(cs.ko, width = 1, fix = "center")
        }
        
        meta.ko = data.frame(
          id = 2,
          condition = factor("KO"),
          clPlus = "ko_plus.bw",
          clMinus = "ko_minus.bw"
        )
        bds.ko.raw = BSFDataSetFromBigWig(ranges = cs.ko, meta = meta.ko, silent = TRUE)
        chrom.ko = as.character(seqnames(cs.ko)[1])
        bds.ko = BSFind(object = bds.ko.raw, anno.genes = gns, anno.transcriptRegionList = regions, est.subsetChromosome = chrom.ko, veryQuiet = TRUE)
        
        # 3. Combine the Datasets
        bds.comb = bds.wt + bds.ko
        
        # 4. Calculate Binding Site and Background Counts
        bds.diff = calculateBsBackground(bds.comb, anno.genes = gns)
        
        # 5. Filter Out Low-Signal or Imbalanced Genes
        bds.diff = filterBsBackground(bds.diff)
        
        # 6. Perform Differential Testing
        bds.diff = calculateBsFoldChange(bds.diff)
        diff_ranges = getRanges(bds.diff)
        
        # Save tabular results
        write.csv(as.data.frame(diff_ranges), "differential_binding_analysis_results.csv", row.names = FALSE)
        saveRDS(bds.diff, "bds_differential_analysis.rds")
        
        # 7. Visualize Results
        pdf("differential_binding_plots.pdf", width = 8, height = 6)
        
        tryCatch({
          plotBsMA(bds.diff, what = "bs")
        }, error = function(e) {
          warning("Could not plot MA plot: ", e\$message)
        })
        
        bds.diff = assignToTranscriptRegions(bds.diff, anno.transcriptRegionList = regions)
        
        tryCatch({
          geneRegulationPlot(bds.diff, plot.geneID = "ENSG00000180957.18", anno.genes = gns)
        }, error = function(e) {
          # If the specific gene ID is not present, try to find a valid one from the results
          valid_genes = unique(diff_ranges\$geneID)
          valid_genes = valid_genes[!is.na(valid_genes)]
          if (length(valid_genes) > 0) {
            tryCatch({
              geneRegulationPlot(bds.diff, plot.geneID = valid_genes[1], anno.genes = gns)
            }, error = function(err) {
              warning("Could not plot gene regulation for alternative gene: ", err\$message)
            })
          } else {
            warning("Could not plot gene regulation: ", e\$message)
          }
        })
        
        dev.off()

    writeLines(c(
        '"BIOC_BINDINGSITEFINDER_DIFFERENTIAL_BINDING_ANALYSIS":',
        paste0('    BindingSiteFinder: ', as.character(packageVersion('BindingSiteFinder')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_differential_binding_analysis.csv versions.yml
    """
}

workflow BIOC_BINDINGSITEFINDER_DIFFERENTIAL_BINDING_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ wt_pureclip.bed, ko_pureclip.bed, wt_plus.bw, wt_minus.bw, ko_plus.bw, ko_minus.bw, gencode_v37_annotation.gff3 ] ]

    main:
    BIOC_BINDINGSITEFINDER_DIFFERENTIAL_BINDING_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_BINDINGSITEFINDER_DIFFERENTIAL_BINDING_ANALYSIS.out.tables
    plots    = BIOC_BINDINGSITEFINDER_DIFFERENTIAL_BINDING_ANALYSIS.out.plots
    objects  = BIOC_BINDINGSITEFINDER_DIFFERENTIAL_BINDING_ANALYSIS.out.objects
    versions = BIOC_BINDINGSITEFINDER_DIFFERENTIAL_BINDING_ANALYSIS.out.versions
}
