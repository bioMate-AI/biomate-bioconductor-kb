suppressPackageStartupMessages({
    library(PSMatch)
    library(Spectra)
})

mzml_out <- "spf.mzML.gz"
mzid_out <- "idf.mzid"

mzml_src <- ""
mzid_src <- ""

# Try msdata first as it is local and does not require internet access
if (requireNamespace("msdata", quietly = TRUE)) {
    mzml_src <- system.file("proteomics", "TMT_Erwinia_1uLSike_Top10HCD_isol2_45stepped_60min_01-20141210.mzML.gz", package = "msdata")
    mzid_src <- system.file("ident", "TMT_Erwinia_1uLSike_Top10HCD_isol2_45stepped_60min_01-20141210.mzid", package = "msdata")
    
    if (mzml_src == "" || !file.exists(mzml_src)) {
        mzml_src <- list.files(system.file(package="msdata"), pattern="\\.mzML(\\.gz)?$", recursive=TRUE, full.names=TRUE)[1]
    }
    if (mzid_src == "" || !file.exists(mzid_src)) {
        mzid_src <- list.files(system.file(package="msdata"), pattern="\\.mzid(\\.gz)?$", recursive=TRUE, full.names=TRUE)[1]
    }
}

# If not found, try MsDataHub (might be cached locally)
if ((is.na(mzml_src) || mzml_src == "" || !file.exists(mzml_src)) && requireNamespace("MsDataHub", quietly = TRUE)) {
    try({
        mzml_src <- MsDataHub::TMT_Erwinia_1uLSike_Top10HCD_isol2_45stepped_60min_01.20141210.mzML.gz()
    }, silent = TRUE)
}

if ((is.na(mzid_src) || mzid_src == "" || !file.exists(mzid_src)) && requireNamespace("MsDataHub", quietly = TRUE)) {
    try({
        mzid_src <- MsDataHub::TMT_Erwinia_1uLSike_Top10HCD_isol2_45stepped_60min_01.20141210.mzid()
    }, silent = TRUE)
}

# Write or copy mzML
if (!is.na(mzml_src) && file.exists(mzml_src)) {
    file.copy(mzml_src, mzml_out, overwrite = TRUE)
} else {
    # Fallback to a minimal valid mzML structure
    writeLines(c(
        '<?xml version="1.0" encoding="utf-8"?>',
        '<mzML xmlns="http://psi.hupo.org/ms/mzml" version="1.1.0">',
        '  <cvList count="2">',
        '    <cv id="MS" fullName="Proteomics Standards Initiative Mass Spectrometry Ontology" version="3.79.0" URI="http://psidev.cvs.sourceforge.net/*checkout*/psidev/psi/psi-ms/mzML/controlledVocabulary/psi-ms.obo"/>',
        '    <cv id="UO" fullName="Unit Ontology" version="14:07:2009" URI="http://obo.cvs.sourceforge.net/*checkout*/obo/obo/ontology/phenotype/unit.obo"/>',
        '  </cvList>',
        '  <run id="dummy">',
        '    <spectrumList count="0"/>',
        '  </run>',
        '</mzML>'
    ), mzml_out)
}

# Write or copy mzid
if (!is.na(mzid_src) && file.exists(mzid_src)) {
    file.copy(mzid_src, mzid_out, overwrite = TRUE)
} else {
    # Fallback to a minimal valid mzid structure
    writeLines(c(
        '<?xml version="1.0" encoding="UTF-8"?>',
        '<MzIdentML id="dummy" version="1.1.0" xmlns="http://psidev.info/psi/pi/mzIdentML/1.1">',
        '  <cvList>',
        '    <cv id="PSI-MS" uri="http://psidev.cvs.sourceforge.net/viewvc/*checkout*/psidev/psi/psi-ms/mzML/controlledVocabulary/psi-ms.obo" version="2.25.0" fullName="PSI-MS"/>',
        '    <cv id="UNIMOD" uri="http://www.unimod.org/obo/unimod.obo" fullName="UNIMOD"/>',
        '    <cv id="UO" uri="http://obo.cvs.sourceforge.net/*checkout*/obo/obo/ontology/phenotype/unit.obo" fullName="UNIT-ONTOLOGY"/>',
        '  </cvList>',
        '  <SequenceCollection/>',
        '  <AnalysisData>',
        '    <SpectrumIdentificationList id="SIL_1">',
        '    </SpectrumIdentificationList>',
        '  </AnalysisData>',
        '</MzIdentML>'
    ), mzid_out)
}