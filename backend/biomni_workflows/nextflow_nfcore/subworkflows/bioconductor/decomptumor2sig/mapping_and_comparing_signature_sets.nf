#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: decomptumor2sig — mapping_and_comparing_signature_sets
// Compare and map two different sets of mutational signatures (even if they are of different formats or models) to find the closest matching signatures.
// Input: Nik-Zainal_PMID_22608084-pmsignature-sig1.tsv to sig4.tsv, Alexandrov_PMID_23945592_435_tumors-pmsignature-15sig.Rdata
// Container: quay.io/biocontainers/bioconductor-decomptumor2sig:2.26.0--r45hdfd78af_0
// R packages: decompTumor2Sig
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DECOMPTUMOR2SIG_MAPPING_AND_COMPARING_SIGNATURE_SETS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-decomptumor2sig:2.26.0--r45hdfd78af_0"

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
    library(decompTumor2Sig)
    
    # --- Load the two sets of mutational signatures from the ---
    # First set: 4 Shiraishi signatures from Nik-Zainal et al.
    sigfiles <- paste0("Nik-Zainal_PMID_22608084-pmsignature-sig", 1:4, ".tsv")
    sign_s4 <- readShiraishiSignatures(files=sigfiles)
    
    # Second set: 15 Shiraishi signatures from Alexandrov et al.
    sfile <- "Alexandrov_PMID_23945592_435_tumors-pmsignature-15sig.Rdata"
    load(sfile)
    sign_s15 <- signatures
    
    # --- Compute distances between a single signature and a target ---
    distances <- determineSignatureDistances(fromSignature=sign_s4[[1]], toSignatures=sign_s15,
                                             method="frobenius")
    
    # --- Map the signature sets to find the best matches ---
    mapping_non_unique <- mapSignatureSets(fromSignatures=sign_s4, toSignatures=sign_s15,
                                           method="frobenius", unique=FALSE)
    
    # --- Convert Alexandrov signatures to Shiraishi format ---
    sign_a <- readAlexandrovSignatures()
    sign_a2s <- convertAlexandrov2Shiraishi(sign_a)
    
    # --- Downgrade Shiraishi signatures to make different formats ---
    sign_sdown <- downgradeShiraishiSignatures(sign_s15, numBases=3,
                                               removeTrDir=TRUE)
    
    # --- Map the converted/downgraded signature sets (unique) ---
    mapping_unique <- mapSignatureSets(fromSignatures=sign_sdown, toSignatures=sign_a2s,
                                       method="frobenius", unique=TRUE)
    
    # --- Write named output files for the meaningful results ---
    # Save distances
    write.csv(as.data.frame(t(distances)), "signature_distances_s4_to_s15.csv", row.names = TRUE)
    
    # Save non-unique mapping
    write.csv(as.data.frame(mapping_non_unique), "mapping_s4_to_s15_non_unique.csv", row.names = TRUE)
    
    # Save unique mapping
    write.csv(as.data.frame(mapping_unique), "mapping_sdown_to_a2s_unique.csv", row.names = TRUE)
    
    # Save converted and downgraded signatures as RDS
    saveRDS(sign_a2s, "sign_a2s.rds")
    saveRDS(sign_sdown, "sign_sdown.rds")

    writeLines(c(
        '"BIOC_DECOMPTUMOR2SIG_MAPPING_AND_COMPARING_SIGNATURE_SETS":',
        paste0('        decomptumor2sig: ', as.character(packageVersion("decomptumor2sig")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mapping_and_comparing_signature_sets.csv versions.yml
    """
}

workflow BIOC_DECOMPTUMOR2SIG_MAPPING_AND_COMPARING_SIGNATURE_SETS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Nik-Zainal_PMID_22608084-pmsignature-sig1.tsv to sig4.tsv, Alexandrov_PMID_23945592_435_tumors-pmsignature-15sig.Rdata ] ]

    main:
    BIOC_DECOMPTUMOR2SIG_MAPPING_AND_COMPARING_SIGNATURE_SETS(ch_input)

    emit:
    tables   = BIOC_DECOMPTUMOR2SIG_MAPPING_AND_COMPARING_SIGNATURE_SETS.out.tables
    plots    = BIOC_DECOMPTUMOR2SIG_MAPPING_AND_COMPARING_SIGNATURE_SETS.out.plots
    objects  = BIOC_DECOMPTUMOR2SIG_MAPPING_AND_COMPARING_SIGNATURE_SETS.out.objects
    versions = BIOC_DECOMPTUMOR2SIG_MAPPING_AND_COMPARING_SIGNATURE_SETS.out.versions
}
