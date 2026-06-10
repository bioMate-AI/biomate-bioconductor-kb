library(IsoBayes)

data_dir <- system.file("extdata", package = "IsoBayes")

# Copy existing files from the package's extdata directory
files_to_copy <- c(
  "AllPeptides.psmtsv",
  "AllQuantifiedPeptides.tsv",
  "jurkat_isoform_kallisto.tsv",
  "map_iso_gene.csv"
)

for (f in files_to_copy) {
  src <- file.path(data_dir, f)
  if (file.exists(src)) {
    file.copy(src, f, overwrite = TRUE)
  } else {
    # Fallback dummy creation if the file is missing from the installation
    if (f == "AllPeptides.psmtsv") {
      dummy_psm <- data.frame(
        `Base Sequence` = c("PEPTIDEONE", "PEPTIDETWO"),
        `Protein Accession` = c("isoform_1", "isoform_1|isoform_2"),
        `QValue` = c(0.01, 0.05),
        `PEP` = c(0.001, 0.01),
        `Decoy/Contaminant/Target` = c("T", "T"),
        check.names = FALSE
      )
      write.table(dummy_psm, f, sep = "\t", row.names = FALSE, quote = FALSE)
    } else if (f == "AllQuantifiedPeptides.tsv") {
      dummy_quant <- data.frame(
        `Base Sequence` = c("PEPTIDEONE", "PEPTIDETWO"),
        `Intensity` = c(1000, 2000),
        check.names = FALSE
      )
      write.table(dummy_quant, f, sep = "\t", row.names = FALSE, quote = FALSE)
    } else if (f == "jurkat_isoform_kallisto.tsv") {
      dummy_tpm <- data.frame(
        isoname = c("isoform_1", "isoform_2"),
        tpm = c(10.5, 5.2)
      )
      write.table(dummy_tpm, f, sep = "\t", row.names = FALSE, quote = FALSE)
    } else if (f == "map_iso_gene.csv") {
      dummy_map <- data.frame(
        isoform = c("isoform_1", "isoform_2"),
        gene = c("gene_A", "gene_A")
      )
      write.csv(dummy_map, f, row.names = FALSE, quote = FALSE)
    }
  }
}

# Construct custom_peptides.tsv (user-provided data alternative)
if (!file.exists("custom_peptides.tsv")) {
  custom_peptides <- data.frame(
    Y = c(10, 20, 5),
    EC = c("isoform_1", "isoform_1|isoform_2", "isoform_2"),
    FDR = c(0.01, 0.05, 0.02),
    PEP = c(0.001, 0.01, 0.005),
    sequence = c("PEPTIDEONE", "PEPTIDETWO", "PEPTIDETHREE")
  )
  write.table(custom_peptides, "custom_peptides.tsv", sep = "\t", row.names = FALSE, quote = FALSE)
}

# Construct file.idXML (OpenMS Percolator output alternative)
if (!file.exists("file.idXML")) {
  idxml_content <- '<?xml version="1.0" encoding="UTF-8"?>
<IdXML version="1.5">
  <IdentificationRun date="2023-01-01T00:00:00">
    <ProteinIdentification score_type="q-value" higher_score_better="false" significance_threshold="0.01">
      <ProteinHit id="PH_1" accession="isoform_1" score="0.0" sequence="MPEPTIDEONE"/>
    </ProteinIdentification>
    <PeptideIdentification score_type="q-value" higher_score_better="false" significance_threshold="0.01" MZ="500.0" RT="1000.0">
      <PeptideHit score="0.0" sequence="PEPTIDEONE" charge="2">
        <PeptideEvidence protein_ref="PH_1"/>
      </PeptideHit>
    </PeptideIdentification>
  </IdentificationRun>
</IdXML>'
  writeLines(idxml_content, "file.idXML")
}