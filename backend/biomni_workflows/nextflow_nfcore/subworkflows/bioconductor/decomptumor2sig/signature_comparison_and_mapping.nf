#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: decompTumor2Sig — signature_comparison_and_mapping
// Compare and map two different sets of mutational signatures, converting or downgrading them to a common format if necessary.
// Input: Nik-Zainal_PMID_22608084-pmsignature-sig1.tsv, Alexandrov_PMID_23945592_435_tumors-pmsignature-15sig.Rdata
// Container: quay.io/biocontainers/bioconductor-decomptumor2sig:2.26.0--r45hdfd78af_0
// Requires: decompTumor2Sig
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the two signature sets. 2. Compute distances from a single signature to a target signature set. 3. Map one signature set to a

nextflow.enable.dsl = 2

process BIOC_DECOMPTUMOR2SIG_SIGNATURE_COMPARISON_AND_MAPPING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
    .bm_deps <- c("decompTumor2Sig")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
    
    # Load required library
    library(decompTumor2Sig)
    
    # 1. Load two distinct sets of Shiraishi signatures from the working directory
    sigfiles <- "Nik-Zainal_PMID_22608084-pmsignature-sig1.tsv"
    sign_s4 <- readShiraishiSignatures(files=sigfiles)
    
    sfile <- "Alexandrov_PMID_23945592_435_tumors-pmsignature-15sig.Rdata"
    load(sfile)
    sign_s15 <- signatures
    
    # 2. Compute distances of one signature to a set
    distances <- determineSignatureDistances(fromSignature=sign_s4[[1]], toSignatures=sign_s15, method="frobenius")
    
    # Save distances to a CSV file
    write.csv(as.data.frame(t(distances)), file="signature_distances.csv", row.names=TRUE)
    
    # 3. Map one signature set to another (non-unique mapping)
    mapping_nonunique <- mapSignatureSets(fromSignatures=sign_s4, toSignatures=sign_s15, method="frobenius", unique=FALSE)
    
    # Save non-unique mapping to a CSV file
    write.csv(as.data.frame(mapping_nonunique), file="signature_mapping_nonunique.csv", row.names=TRUE)
    
    # 4. Convert and downgrade signatures for cross-format comparison
    sign_a <- readAlexandrovSignatures()
    sign_a2s <- convertAlexandrov2Shiraishi(sign_a)
    sign_sdown <- downgradeShiraishiSignatures(sign_s15, numBases=3, removeTrDir=TRUE)
    
    # Map downgraded signatures to converted signatures (unique mapping)
    mapping_unique <- mapSignatureSets(fromSignatures=sign_sdown, toSignatures=sign_a2s, method="frobenius", unique=TRUE)
    
    # Save unique mapping to a CSV file
    write.csv(as.data.frame(mapping_unique), file="signature_mapping_unique.csv", row.names=TRUE)
    
    # Save converted and downgraded signatures as RDS for downstream use
    saveRDS(sign_a2s, file="converted_alexandrov_to_shiraishi.rds")
    saveRDS(sign_sdown, file="downgraded_shiraishi_signatures.rds")

    writeLines(c(
        '"BIOC_DECOMPTUMOR2SIG_SIGNATURE_COMPARISON_AND_MAPPING":',
        paste0('    decompTumor2Sig: ', as.character(packageVersion('decompTumor2Sig')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_signature_comparison_and_mapping.csv versions.yml
    """
}

workflow BIOC_DECOMPTUMOR2SIG_SIGNATURE_COMPARISON_AND_MAPPING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Nik-Zainal_PMID_22608084-pmsignature-sig1.tsv, Alexandrov_PMID_23945592_435_tumors-pmsignature-15sig.Rdata ] ]

    main:
    BIOC_DECOMPTUMOR2SIG_SIGNATURE_COMPARISON_AND_MAPPING(ch_input)

    emit:
    tables   = BIOC_DECOMPTUMOR2SIG_SIGNATURE_COMPARISON_AND_MAPPING.out.tables
    plots    = BIOC_DECOMPTUMOR2SIG_SIGNATURE_COMPARISON_AND_MAPPING.out.plots
    objects  = BIOC_DECOMPTUMOR2SIG_SIGNATURE_COMPARISON_AND_MAPPING.out.objects
    versions = BIOC_DECOMPTUMOR2SIG_SIGNATURE_COMPARISON_AND_MAPPING.out.versions
}
