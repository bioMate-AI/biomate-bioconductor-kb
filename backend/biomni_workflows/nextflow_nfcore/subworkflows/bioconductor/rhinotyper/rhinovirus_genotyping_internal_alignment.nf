#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: rhinotyper — rhinovirus_genotyping_internal_alignment
// Genotype rhinovirus sequences by aligning them directly in R with packaged prototype references, followed by downstream distance and visualization analyses.
// Input: user_sequences.fasta
// Container: quay.io/biocontainers/bioconductor-rhinotyper:1.4.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RHINOTYPER_RHINOVIRUS_GENOTYPING_INTERNAL_ALIGNMENT {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-rhinotyper:1.4.0--r45hdfd78af_0"

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
    .bm_deps <- c("Biostrings", "msa", "rhinotypeR")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(rhinotypeR)
    library(Biostrings)
    library(msa)
    
    # 1. Read user sequences from the working directory
    user_seqs <- Biostrings::readDNAStringSet("user_sequences.fasta")
    
    # 2. Align user sequences and packaged prototypes in R
    aln <- alignToRefs(
      seqData   = user_seqs,
      method    = "ClustalW",           # or "ClustalOmega", "Muscle"
      trimToRef = TRUE,                 # crop to reference non-gap span
      refName   = "JN855971.1_A107"     # default anchor; change if desired
    )
    
    # Save alignment object
    saveRDS(aln, "alignment_results.rds")
    
    # 3. Assign genotypes
    res <- assignTypes(aln, model = "IUPAC", deleteGapsGlobally = FALSE, threshold = 0.105)
    
    # Save genotype assignments table
    write.csv(res, "genotype_assignments.csv", row.names = FALSE)
    
    # 4. Plot genotype frequencies
    pdf("genotype_frequencies.pdf", width = 8, height = 6)
    plotFrequency(res)
    dev.off()
    
    # 5. Translate DNA sequences and visualize amino acid alignments
    aln_no_gaps <- Biostrings::DNAStringSet(
      gsub("-", "", as.character(user_seqs))
    )
    
    aa <- Biostrings::translate(aln_no_gaps)
    aa_aln <- msa::msa(aa)  # align as plotAA expects equal width
    aa_aln <- as(aa_aln, "AAStringSet") # transform to AAStringSet
    
    # Save AA alignment object
    saveRDS(aa_aln, "aa_alignment.rds")
    
    # Plot AA alignment
    pdf("amino_acid_alignment.pdf", width = 10, height = 8)
    plotAA(aa_aln)
    dev.off()

    cat <<-END_VERSIONS > versions.yml
    "BIOC_RHINOTYPER_RHINOVIRUS_GENOTYPING_INTERNAL_ALIGNMENT":
        rhinotyper: \$(Rscript -e 'cat(as.character(packageVersion("rhinotyper")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rhinovirus_genotyping_internal_alignment.csv versions.yml
    """
}

workflow BIOC_RHINOTYPER_RHINOVIRUS_GENOTYPING_INTERNAL_ALIGNMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ user_sequences.fasta ] ]

    main:
    BIOC_RHINOTYPER_RHINOVIRUS_GENOTYPING_INTERNAL_ALIGNMENT(ch_input)

    emit:
    tables   = BIOC_RHINOTYPER_RHINOVIRUS_GENOTYPING_INTERNAL_ALIGNMENT.out.tables
    plots    = BIOC_RHINOTYPER_RHINOVIRUS_GENOTYPING_INTERNAL_ALIGNMENT.out.plots
    objects  = BIOC_RHINOTYPER_RHINOVIRUS_GENOTYPING_INTERNAL_ALIGNMENT.out.objects
    versions = BIOC_RHINOTYPER_RHINOVIRUS_GENOTYPING_INTERNAL_ALIGNMENT.out.versions
}
