#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: seqLogo — sequence_logo_generation
// Generate and customize sequence logos from a position weight matrix of DNA or RNA sequences.
// Input: pwm_matrix.txt
// Container: quay.io/biocontainers/bioconductor-seqlogo:1.76.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: seqLogo
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the package and read the position weight matrix from a file
//  * 2. [Input & Preparation] Create a PWM object using makePWM()
//  * 3. [Core Analysis] Access PWM slots like information content and consensus sequence
//  * 4. [Visualization & Output] Plot the sequence logo using seqLogo(), optionally adjusting information content scaling, colors, or alphabet (DNA/RNA)

nextflow.enable.dsl = 2

process BIOC_SEQLOGO_SEQUENCE_LOGO_GENERATION {
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
    .bm_deps <- c("seqLogo")
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
    
    # 1. Load the package and read the position weight matrix from a file
    library(seqLogo)
    
    # Read the user-provided PWM matrix from the working directory
    m <- read.table("pwm_matrix.txt")
    
    # 2. Create a PWM object using makePWM()
    p <- makePWM(m)
    
    # 3. Access PWM slots like information content and consensus sequence
    s_names <- slotNames(p)
    p_matrix <- pwm(p)
    ic_profile <- ic(p)
    cons_seq <- consensus(p)
    
    # Print accessed slot information to stdout
    print(s_names)
    print(p_matrix)
    print(ic_profile)
    print(cons_seq)
    
    # Save accessed slot information to output files
    write.table(p_matrix, file = "pwm_matrix_output.txt", sep = "\t", quote = FALSE, col.names = NA)
    writeLines(cons_seq, con = "consensus_sequence.txt")
    write.table(data.frame(Position = seq_along(ic_profile), InformationContent = ic_profile), 
                file = "information_content.txt", sep = "\t", quote = FALSE, row.names = FALSE)
    saveRDS(p, file = "pwm_dna_object.rds")
    
    # 4. Plot the sequence logo using seqLogo(), optionally adjusting information content scaling, colors, or alphabet (DNA/RNA)
    pdf("sequence_logos.pdf", width = 7, height = 5)
    
    # Plot 1: Default sequence logo
    seqLogo(p)
    
    # Plot 2: Sequence logo with uniform column heights
    seqLogo(p, ic.scale=FALSE)
    
    # Plot 3: Sequence logo with user-specified colors
    seqLogo(p, fill=c(A="#4daf4a", C="#377eb8", G="#ffd92f", T="#e41a1c"),
            ic.scale=FALSE)
    
    # Plot 4: RNA Sequence logo
    r <- makePWM(m, alphabet="RNA")
    seqLogo(r, ic.scale=FALSE)
    
    dev.off()
    
    # Save RNA PWM object
    saveRDS(r, file = "pwm_rna_object.rds")

    writeLines(c(
        '"BIOC_SEQLOGO_SEQUENCE_LOGO_GENERATION":',
        paste0('    seqLogo: ', as.character(packageVersion('seqLogo')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sequence_logo_generation.csv versions.yml
    """
}

workflow BIOC_SEQLOGO_SEQUENCE_LOGO_GENERATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ pwm_matrix.txt ] ]

    main:
    BIOC_SEQLOGO_SEQUENCE_LOGO_GENERATION(ch_input)

    emit:
    tables   = BIOC_SEQLOGO_SEQUENCE_LOGO_GENERATION.out.tables
    plots    = BIOC_SEQLOGO_SEQUENCE_LOGO_GENERATION.out.plots
    objects  = BIOC_SEQLOGO_SEQUENCE_LOGO_GENERATION.out.objects
    versions = BIOC_SEQLOGO_SEQUENCE_LOGO_GENERATION.out.versions
}
