#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: iSeq — iseq2_high_order_ising
// Build dynamic signal profiles and identify enriched genomic regions using a high-order hidden Ising model with a fixed interaction parameter (iSeq2), suitable f
// Input: chip_tags.txt, control_tags.txt
// Container: quay.io/biocontainers/bioconductor-iseq:1.62.0--r45h01b2380_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: iSeq
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Adjust tag start positions to middle positions
//  * 2. [Input & Preparation] Build dynamic signal profiles using mergetag
//  * 3. [Core Analysis] Fit the high-order hidden Ising model using iSeq2
//  * 4. [Core Analysis] Call enriched regions using peakreg with a posterior probability cutoff

nextflow.enable.dsl = 2

process BIOC_ISEQ_ISEQ2_HIGH_ORDER_ISING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20"

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
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required library
    library(iSeq)
    
    # 1. Read user input files from the working directory
    if (!file.exists("chip_tags.txt") || !file.exists("control_tags.txt")) {
      stop("Error: Required input files 'chip_tags.txt' and/or 'control_tags.txt' not found in the working directory.")
    }
    
    chip = read.table("chip_tags.txt", header=TRUE, stringsAsFactors=FALSE)
    mock = read.table("control_tags.txt", header=TRUE, stringsAsFactors=FALSE)
    
    # Ensure columns are in the correct order: chr, position, strand
    chip = chip[, c("chr", "position", "strand")]
    mock = mock[, c("chr", "position", "strand")]
    
    # 2. Adjust tag start positions to middle positions (assuming 25 bp reads, adding 12 bp)
    chip[,2] = chip[,2]+12
    mock[,2] = mock[,2]+12
    
    # 3. Build dynamic signal profiles using mergetag
    tagct = mergetag(chip=chip,control=mock,maxlen=80,minlen=10,ntagcut=10)
    
    # Determine which chromosome to analyze (prefer chr22 if present, otherwise use the first available)
    chroms = unique(tagct[,1])
    target_chrom = if ("chr22" %in% chroms) "chr22" else chroms[1]
    message(paste("Analyzing chromosome:", target_chrom))
    
    tagct22 = tagct[tagct[,1] == target_chrom, ]
    
    # 4. Fit the high-order hidden Ising model using iSeq2
    res2 = iSeq2(Y=tagct22[,1:4],gap=200, burnin=100,sampling=500,winsize=2,
         ctcut=0.95,a0=1,b0=1,a1=5,b1=1,k=1.0,verbose=FALSE)
    
    # Save the model results object
    saveRDS(res2, file="iseq2_results.rds")
    
    # 5. Call enriched regions using peakreg with a posterior probability cutoff
    reg2 = peakreg(tagct22[,1:3],tagct22[,5:6],res2\$pp,0.5,method="ppcut",maxgap=200)
    
    # Save the called enriched regions to a CSV table
    write.csv(reg2, file="enriched_regions_iseq2.csv", row.names=FALSE)
    
    # 6. Generate diagnostic and visualization plots
    pdf("iseq2_diagnostics.pdf", width=8, height=8)
    par(mfrow=c(2,2), mar=c(4.1, 4.1, 2.0, 1.0))
    
    # Plot posterior probabilities histogram
    hist(res2\$pp, main="Posterior Probabilities", xlab="pp")
    
    # Plot trace plots for lambda0 and lambda1 parameters to assess MCMC convergence
    plot(res2\$lambda0, pch=".", xlab="Iterations", ylab="lambda0", main="Trace plot: lambda0")
    plot(res2\$lambda1, pch=".", xlab="Iterations", ylab="lambda1", main="Trace plot: lambda1")
    
    # Plot up to 4 enriched regions if they exist
    if (!is.null(reg2) && nrow(reg2) > 0) {
      n_plots = min(4, nrow(reg2))
      for(i in 1:n_plots){
        ID = (reg2[i,4]):(reg2[i,5])
        # Ensure indices are within valid bounds of the data frame
        if (all(ID >= 1 & ID <= nrow(tagct22))) {
          plotreg(tagct22[ID,2:3],tagct22[ID,5:6],tagct22[ID,7:8],peak=reg2[i,6])
        }
      }
    } else {
      plot.new()
      text(0.5, 0.5, "No enriched regions found to plot", cex=1.2)
    }
    
    dev.off()
    
    message("Pipeline completed successfully. Outputs saved: iseq2_results.rds, enriched_regions_iseq2.csv, iseq2_diagnostics.pdf")

    writeLines(c(
        '"BIOC_ISEQ_ISEQ2_HIGH_ORDER_ISING":',
        paste0('    iSeq: ', as.character(packageVersion('iSeq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_iseq2_high_order_ising.csv versions.yml
    """
}

workflow BIOC_ISEQ_ISEQ2_HIGH_ORDER_ISING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ chip_tags.txt, control_tags.txt ] ]

    main:
    BIOC_ISEQ_ISEQ2_HIGH_ORDER_ISING(ch_input)

    emit:
    tables   = BIOC_ISEQ_ISEQ2_HIGH_ORDER_ISING.out.tables
    plots    = BIOC_ISEQ_ISEQ2_HIGH_ORDER_ISING.out.plots
    objects  = BIOC_ISEQ_ISEQ2_HIGH_ORDER_ISING.out.objects
    versions = BIOC_ISEQ_ISEQ2_HIGH_ORDER_ISING.out.versions
}
