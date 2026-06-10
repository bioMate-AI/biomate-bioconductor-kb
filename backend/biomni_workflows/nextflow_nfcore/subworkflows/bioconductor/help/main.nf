#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: help — help_methylation_pipeline
// Import, normalize, summarize, and visualize DNA methylation data from HELP assay microarrays.
// Input: msp1.files, hpa2.files, sample.key.txt, HELP.ndf.txt, HELP.ngd.txt
// Container: quay.io/biocontainers/bioconductor-help:1.68.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_HELP_HELP_METHYLATION_PIPELINE {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-help:1.68.0--r45hdfd78af_0"

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
    .bm_deps <- c("help")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    library(HELP)
    
    # 1. Import raw pair files
    msp1.files <- dir(".", pattern="532[._]pair", full.names=TRUE)
    hpa2.files <- dir(".", pattern="635[._]pair", full.names=TRUE)
    N <- length(msp1.files)
    for (i in 1:N) {
    	if (i == 1) {
    		pairs <- readPairs(msp1.files[i],hpa2.files[i])
    	}
    	else {
    		pairs <- readPairs(msp1.files[i],hpa2.files[i],pairs)
    	}
    }
    
    # 2. Map chip IDs to human-readable sample names
    chips <- sub("[_.]*532[_.]*pair.*","",basename(msp1.files))
    samplekey <- "sample.key.txt"
    chips <- readSampleKey(file=samplekey,chips=chips)
    sampleNames(pairs) <- chips
    
    # 3. Load design and genomic feature information
    ndf.file <- "HELP.ndf.txt"
    ngd.file <- "HELP.ngd.txt"
    pairs <- readDesign(ndf.file, ngd.file, pairs)
    
    # 4. Calculate probe properties
    tm_single <- calcTm("ATCTAGGAAGATTTAGAGAGGCAATGTGTCATTTAGCATCTAATTTTACC")
    tm_multi <- calcTm(getFeatures(pairs,"SEQUENCE")[1:4])
    gc_single <- calcGC("ATCTAGGAAGATTTAGAGAGGCAATGTGTCATTTAGCATCTAATTTTACC")
    gc_multi <- calcGC(getFeatures(pairs,"SEQUENCE")[1:4])
    
    tm_gc_results <- data.frame(
      Sequence = c("ATCTAGGAAGATTTAGAGAGGCAATGTGTCATTTAGCATCTAATTTTACC", getFeatures(pairs,"SEQUENCE")[1:4]),
      Tm = c(tm_single, tm_multi),
      GC = c(gc_single, gc_multi)
    )
    write.csv(tm_gc_results, "tm_gc_results.csv", row.names=FALSE)
    
    # 5. Quality control and exploration
    samples_head <- getSamples(pairs)[1:4,]
    write.csv(samples_head, "samples_head.csv")
    
    proto <- calcPrototype(pairs,center=FALSE)[1:4]
    write.csv(as.data.frame(proto), "prototype_results.csv")
    
    pdf("chip_plot_Brain2.pdf")
    plotChip(pairs, sample="Brain2")
    dev.off()
    
    exprs(pairs) <- log2(exprs(pairs))
    exprs2(pairs) <- log2(exprs2(pairs))
    
    pdf("feature_plot_Brain2.pdf")
    plotFeature(pairs[,"Brain2"],cex=0.5)
    dev.off()
    
    # 6. Identify background noise thresholds
    rand <- which(getFeatures(pairs, "TYPE")=="RAND")
    msp.rand <- getSamples(pairs, element="exprs")[rand,]
    hpa.rand <- getSamples(pairs, element="exprs2")[rand,]
    msp.rand.med <- apply(msp.rand, 2, median)
    msp.rand.mad <- apply(msp.rand, 2, mad)
    hpa.rand.med <- apply(hpa.rand, 2, median)
    hpa.rand.mad <- apply(hpa.rand, 2, mad)
    msp.fail <- msp.rand.med + 2.5*msp.rand.mad
    hpa.fail <- hpa.rand.med + 2.5*hpa.rand.mad
    hpa.meth <- apply(hpa.rand, 2, quantile, 0.99)
    
    # 7. Single-sample quantile normalization
    norand <- which(getFeatures(pairs, "TYPE")=="DATA")
    size <- as.numeric(getFeatures(pairs, "SIZE"))[norand]
    msp <- getSamples(pairs, "Brain2", element="exprs")[norand]
    hpa <- getSamples(pairs, "Brain2", element="exprs2")[norand]
    nofail <- which(msp>msp.fail["Brain2"] | hpa>hpa.fail["Brain2"])
    msp.norm <- msp
    msp.norm[nofail] <- quantileNormalize(msp[nofail],size[nofail])
    meth <- which(msp>msp.fail["Brain2"] & hpa<=hpa.meth["Brain2"])
    hpa.norm <- hpa
    hpa.norm[meth] <- quantileNormalize(hpa[meth],size[meth])
    nometh <- which(hpa>hpa.meth["Brain2"])
    hpa.norm[nometh] <- quantileNormalize(hpa[nometh],size[nometh])
    
    pairs.norm <- pairs
    exprs(pairs.norm)[norand, "Brain2"] <- msp.norm
    exprs2(pairs.norm)[norand, "Brain2"] <- hpa.norm
    
    saveRDS(pairs.norm, "pairs_normalized.rds")
    
    # 8. Summarize probe-level data
    data <- getSamples(pairs,element="exprs2")
    seqids <- getFeatures(pairs,'SEQ_ID')
    weight <- getSamples(pairs,element="exprs")
    comb1 <- combineData(data, seqids, weight, trim=0.2)[1:5,]
    write.csv(comb1, "combined_data_weighted_head.csv")
    
    comb2 <- combineData(pairs, feature.group='SEQ_ID', trim=0.2)[1:5,]
    write.csv(comb2, "combined_data_unweighted_head.csv")
    
    # 9. Visualize sample relationships
    pdf("pairs_plot.pdf")
    plotPairs(pairs,element="exprs2")
    dev.off()

    cat <<-END_VERSIONS > versions.yml
    "BIOC_HELP_HELP_METHYLATION_PIPELINE":
        help: \$(Rscript -e 'cat(as.character(packageVersion("help")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_help_methylation_pipeline.csv versions.yml
    """
}

workflow BIOC_HELP_HELP_METHYLATION_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ msp1.files, hpa2.files, sample.key.txt, HELP.ndf.txt, HELP.ngd.txt ] ]

    main:
    BIOC_HELP_HELP_METHYLATION_PIPELINE(ch_input)

    emit:
    tables   = BIOC_HELP_HELP_METHYLATION_PIPELINE.out.tables
    plots    = BIOC_HELP_HELP_METHYLATION_PIPELINE.out.plots
    objects  = BIOC_HELP_HELP_METHYLATION_PIPELINE.out.objects
    versions = BIOC_HELP_HELP_METHYLATION_PIPELINE.out.versions
}
