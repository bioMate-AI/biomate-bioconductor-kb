#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: iSeq — iseq1_standard_ising
// Build dynamic signal profiles and identify enriched genomic regions using a fully Bayesian standard 1D hidden Ising model (iSeq1).
// Input: chip_tags.txt, control_tags.txt
// Container: quay.io/biocontainers/bioconductor-iseq:1.62.0--r45h01b2380_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: iSeq
// Visualizations: enrichment plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Adjust tag start positions to middle positions
//  * 2. [Input & Preparation] Build dynamic signal profiles using mergetag
//  * 3. [Core Analysis] Fit the standard hidden Ising model using iSeq1
//  * 4. [Core Analysis] Call enriched regions using peakreg with posterior probability or FDR cutoffs
//  * 5. [Visualization & Output] Format output as a BED file

nextflow.enable.dsl = 2

process BIOC_ISEQ_ISEQ1_STANDARD_ISING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20-slim"

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
    .bm_deps <- c("iSeq")
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
    library(iSeq)
    
    # Read user input files from the working directory
    chip <- read.table("chip_tags.txt", header=TRUE, stringsAsFactors=FALSE)
    mock <- read.table("control_tags.txt", header=TRUE, stringsAsFactors=FALSE)
    
    # Adjust tag start positions to middle positions (assuming 25 bp reads, adding 12 bp)
    chip[,2] = chip[,2]+12
    mock[,2] = mock[,2]+12
    
    # Build dynamic signal profiles using mergetag
    tagct = mergetag(chip=chip,control=mock,maxlen=80,minlen=10,ntagcut=10)
    
    # Filter for chr22 as documented. 
    # To ensure robustness if the input data does not contain chr22, 
    # we fallback to the first available chromosome while keeping the variable name.
    tagct22 = tagct[tagct[,1]=="chr22",]
    if (nrow(tagct22) == 0) {
        tagct22 = tagct[tagct[,1] == tagct[1,1], ]
    }
    
    # Fit the standard hidden Ising model using iSeq1
    set.seed(777)
    res1 = iSeq1(Y=tagct22[,1:4],gap=200,burnin=200,sampling=1000,ctcut=0.95,
         a0=1,b0=1,a1=5,b1=1,k0=3,mink=0,maxk=10,normsd=0.1,verbose=FALSE)
    
    # Call enriched regions using peakreg with posterior probability cutoff
    reg1 = peakreg(chrpos=tagct22[,1:3],count=(tagct22[,5:6]-tagct22[,7:8]),pp=res1\$pp,
         cutoff=0.5,method="ppcut",maxgap=200)
    
    # Call enriched regions using peakreg with FDR cutoff
    reg2 = peakreg(tagct22[,1:3],tagct22[,5:6]-tagct22[,7:8],res1\$pp,0.05,
         method="fdrcut",maxgap=200)
    
    # Format output as a BED file
    bed = data.frame(chr=reg2[,1],gstart=reg2[,6]-100,gend=reg2[,6]+100)
    
    # Write outputs to files
    saveRDS(res1, file="iseq1_model_fit.rds")
    write.csv(reg1, file="peaks_ppcut_0.5.csv", row.names=FALSE)
    write.csv(reg2, file="peaks_fdrcut_0.05.csv", row.names=FALSE)
    write.table(bed, file="peaks_fdrcut.bed", sep="\t", row.names=FALSE, col.names=FALSE, quote=FALSE)
    
    # Generate diagnostic plots
    pdf("diagnostic_plots.pdf", width=8, height=8)
    par(mfrow=c(2,2), mar=c(4.1, 4.1, 2.0, 1.0))
    hist(res1\$pp, main="Posterior Probabilities", xlab="pp")
    plot(res1\$kappa, pch=".", xlab="Iterations", ylab="kappa")
    plot(res1\$lambda0, pch=".", xlab="Iterations", ylab="lambda0")
    plot(res1\$lambda1, pch=".", xlab="Iterations", ylab="lambda1")
    dev.off()
    
    # Generate enriched region plots if regions are detected
    if (nrow(reg1) > 0) {
        pdf("enriched_regions_plots.pdf", width=8, height=8)
        par(mfrow=c(2,2), mar=c(4.1, 4.1, 2.0, 1.0))
        num_plots <- min(4, nrow(reg1))
        for(i in 1:num_plots){
            ID = (reg1[i,4]):(reg1[i,5])
            plotreg(tagct22[ID,2:3],tagct22[ID,5:6],tagct22[ID,7:8],peak=reg1[i,6])
        }
        dev.off()
    }

    writeLines(c(
        '"BIOC_ISEQ_ISEQ1_STANDARD_ISING":',
        paste0('    iSeq: ', as.character(packageVersion('iSeq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_iseq1_standard_ising.csv versions.yml
    """
}

workflow BIOC_ISEQ_ISEQ1_STANDARD_ISING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ chip_tags.txt, control_tags.txt ] ]

    main:
    BIOC_ISEQ_ISEQ1_STANDARD_ISING(ch_input)

    emit:
    tables   = BIOC_ISEQ_ISEQ1_STANDARD_ISING.out.tables
    plots    = BIOC_ISEQ_ISEQ1_STANDARD_ISING.out.plots
    objects  = BIOC_ISEQ_ISEQ1_STANDARD_ISING.out.objects
    versions = BIOC_ISEQ_ISEQ1_STANDARD_ISING.out.versions
}
