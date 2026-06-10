library(CluMSID)
library(CluMSIDdata)
library(readr)

# 1. Generate dummy mzML files
mzml_files <- c(
    "YH1_GA7_01_10463.mzML",
    "AX1_GB5_01_10470.mzML",
    "LP1_GB3_01_10467.mzML",
    "BR1_GB6_01_10471.mzML"
)

# Try to find a real mzML file from the commonly installed msdata package
source_mzml <- ""
if (requireNamespace("msdata", quietly = TRUE)) {
    source_mzml <- system.file("microtofq", "MM14.mzML", package = "msdata")
    if (!file.exists(source_mzml)) {
        mzml_cands <- list.files(system.file("sciex", package = "msdata"), pattern = "mzML$", full.names = TRUE)
        if (length(mzml_cands) > 0) {
            source_mzml <- mzml_cands[1]
        }
    }
}

for (f in mzml_files) {
    if (file.exists(source_mzml)) {
        file.copy(source_mzml, f, overwrite = TRUE)
    } else {
        # Write a minimal valid mzML if no source is found to satisfy parsers
        writeLines('<?xml version="1.0" encoding="utf-8"?>
<mzML xmlns="http://psi.hupo.org/ms/mzml" version="1.1.0">
  <cvList count="2">
    <cv id="MS" fullName="Proteomics Standards Initiative Mass Spectrometry Ontology" version="3.79.0" URI="http://psidev.cvs.sourceforge.net/*checkout*/psidev/psi/psi-ms/mzML/controlledVocabulary/psi-ms.obo"/>
    <cv id="UO" fullName="Unit Ontology" version="14:07:2009" URI="http://obo.cvs.sourceforge.net/*checkout*/obo/obo/ontology/phenotype/unit.obo"/>
  </cvList>
  <run id="run1">
    <spectrumList count="0">
    </spectrumList>
  </run>
</mzML>', f)
    }
}

# 2. Generate the external peak list and annotation table (MAF format)
maf_file <- "m_mtbls433_metabolite_profiling_mass_spectrometry_v2_maf.tsv"
maf_data <- data.frame(
    database_identifier = c("CHEBI:12345", "CHEBI:67890"),
    chemical_formula = c("C6H12O6", "C2H6O"),
    smiles = c("C(C1C(C(C(C(O1)O)O)O)O)O", "CCO"),
    inchi = c("InChI=1S/C6H12O6/c7-1-2-3(8)4(9)5(10)6(11)12-2/h2-11H,1H2/t2-,3-,4+,5-,6?/m1/s1", "InChI=1S/C2H6O/c1-2-3/h3H,2H2,1H3"),
    metabolite_identification = c("Glucose", "Ethanol"),
    mass_to_charge = c(180.0634, 46.0419),
    retention_time = c(5.2, 1.5),
    stringsAsFactors = FALSE
)

write.table(maf_data, maf_file, sep = "\t", row.names = FALSE, quote = FALSE)

# Verify all files exist
stopifnot(all(file.exists(mzml_files)))
stopifnot(file.exists(maf_file))