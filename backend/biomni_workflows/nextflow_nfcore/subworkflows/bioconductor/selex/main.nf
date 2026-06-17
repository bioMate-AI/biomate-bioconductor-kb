#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: SELEX — selex_seq_analysis
// Quantify DNA binding specificities and estimate K-mer affinities from SELEX-seq data.
// Input: sample_annotation.xml, R0.fastq.gz, R2.fastq.gz
// Container: quay.io/biocontainers/bioconductor-selex:1.42.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SELEX
// Visualizations: bar plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Configure workspace and set Java memory options
//  * 2. [Input & Preparation] Load sample annotations and define sample handles for training, testing, and selected rounds
//  * 3. [Core Analysis] Determine the maximum K-mer length (Kmax) for cross-validation
//  * 4. [Input & Preparation] Build and evaluate Markov models of the initial pool to select the optimal order
//  * 5. [Core Analysis] Calculate information gain across different oligonucleotide lengths to find the optimal motif length
//  * 6. [Core Analysis] Generate K-mer count tables and estimate relative affinities and standard errors

nextflow.enable.dsl = 2

process BIOC_SELEX_SELEX_SEQ_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("SELEX")
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
        
    # Set Java memory limit before loading SELEX to prevent out-of-memory errors
    options(java.parameters="-Xmx1500M")
    library(SELEX)
    
    # Define working directory and ensure it exists
    workDir = "./cache/"
    if (!dir.exists(workDir)) {
      dir.create(workDir, recursive = TRUE)
    }
    
    # Copy user-provided FASTQ files to the cache directory as expected by the XML annotation
    if (file.exists("R0.fastq.gz")) {
      file.copy("R0.fastq.gz", file.path(workDir, "R0.fastq.gz"), overwrite = TRUE)
    }
    if (file.exists("R2.fastq.gz")) {
      file.copy("R2.fastq.gz", file.path(workDir, "R2.fastq.gz"), overwrite = TRUE)
    }
    
    # Configure SELEX workspace
    selex.config(workingDir=workDir, maxThreadNumber=4)
    
    # Load sample annotations from the user-provided XML file
    selex.loadAnnotation("sample_annotation.xml")
    
    # Display sample summary
    samples = selex.sampleSummary()
    print(samples)
    
    # Define sample handles for training, testing, and selected rounds
    r0_idx = which(samples\$rounds == 0)
    r2_idx = which(samples\$rounds == 2)
    
    r0train = selex.sample(seqName=as.character(samples\$seqName[r0_idx[1]]), 
                sampleName=as.character(samples\$sampleName[r0_idx[1]]), round=0)
    
    r0test_idx = ifelse(length(r0_idx) > 1, r0_idx[2], r0_idx[1])
    r0test = selex.sample(seqName=as.character(samples\$seqName[r0test_idx]), 
               sampleName=as.character(samples\$sampleName[r0test_idx]), round=0)
    
    r2 = selex.sample(seqName=as.character(samples\$seqName[r2_idx[1]]), 
           sampleName=as.character(samples\$sampleName[r2_idx[1]]), round=2)
    
    # Determine the maximum K-mer length (Kmax) for cross-validation
    kmax.value = selex.kmax(sample=r0test)
    
    # Build and evaluate Markov models of the initial pool to select the optimal order
    mm = selex.mm(sample=r0train, order=NA, 
           crossValidationSample=r0test, Kmax=kmax.value)
    
    # Save Markov Model summary to CSV
    mm_summary = selex.mmSummary()
    write.csv(mm_summary, "markov_model_summary.csv", row.names=FALSE)
    
    # Plot Markov Model R2 and save to PDF
    pdf("markov_model_r2.pdf")
    mm.r2 = selex.mmSummary()
    idx = which(mm.r2\$R==max(mm.r2\$R))[1]
    colstring = rep('BLUE', nrow(mm.r2))
    colstring[idx] = 'RED'
    barplot(height=mm.r2\$R, names.arg=(mm.r2\$Order), ylim=c(.98,1), xpd=FALSE, col=colstring, 
            xlab="Markov Model Order", ylab=expression(Markov ~ Model ~ R^{2}))
    dev.off()
    
    # Calculate information gain across different oligonucleotide lengths
    selex.infogain(sample=r2, markovModel=mm)
    
    # Save Information Gain summary to CSV
    ig_summary = selex.infogainSummary()
    write.csv(ig_summary, "information_gain_summary.csv", row.names=FALSE)
    
    # Plot Information Gain and find the optimal motif length
    pdf("information_gain.pdf")
    infoscores = selex.infogainSummary()
    idx = which(infoscores\$InformationGain==max(infoscores\$InformationGain))[1]
    colstring = rep('BLUE', nrow(infoscores))
    colstring[idx] = 'RED'
    barplot(height=infoscores\$InformationGain, names.arg=infoscores\$K, col=colstring,
            xlab="Oligonucleotide Length (bp)", ylab="Information Gain (bits)")
    dev.off()
    
    optimalLength = infoscores\$K[idx]
    
    # Generate K-mer count tables for the optimal length
    table = selex.counts(sample=r2, k=optimalLength, 
              markovModel=mm)
    write.csv(table, "kmer_counts.csv", row.names=FALSE)
    
    # Estimate relative affinities and standard errors
    aff = selex.affinities(sample=r2, k=optimalLength, 
            markovModel=mm)
    write.csv(aff, "kmer_affinities.csv", row.names=FALSE)
    
    # Save key objects as RDS for downstream analysis
    saveRDS(mm, "markov_model.rds")
    saveRDS(aff, "affinities.rds")

    writeLines(c(
        '"BIOC_SELEX_SELEX_SEQ_ANALYSIS":',
        paste0('    SELEX: ', as.character(packageVersion('SELEX')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_selex_seq_analysis.csv versions.yml
    """
}

workflow BIOC_SELEX_SELEX_SEQ_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sample_annotation.xml, R0.fastq.gz, R2.fastq.gz ] ]

    main:
    BIOC_SELEX_SELEX_SEQ_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SELEX_SELEX_SEQ_ANALYSIS.out.tables
    plots    = BIOC_SELEX_SELEX_SEQ_ANALYSIS.out.plots
    objects  = BIOC_SELEX_SELEX_SEQ_ANALYSIS.out.objects
    versions = BIOC_SELEX_SELEX_SEQ_ANALYSIS.out.versions
}
