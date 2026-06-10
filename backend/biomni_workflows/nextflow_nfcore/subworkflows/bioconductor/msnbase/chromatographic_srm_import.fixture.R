library(MSnbase)

# Attempt to find an existing mzML file, preferably an MRM/SRM one from the msdata package
mzml_files <- character(0)
if (requireNamespace("msdata", quietly = TRUE)) {
    mzml_files <- list.files(system.file(package = "msdata"), pattern = "\\.mzML$", recursive = TRUE, full.names = TRUE)
}

# Fallback to MSnbase extdata if msdata is not available
if (length(mzml_files) == 0) {
    mzml_files <- list.files(system.file("extdata", package = "MSnbase"), pattern = "\\.mzML$", recursive = TRUE, full.names = TRUE)
}

# Prefer files that are explicitly MRM/SRM
mrm_files <- mzml_files[grepl("mrm|srm", mzml_files, ignore.case = TRUE)]

if (length(mrm_files) > 0) {
    file.copy(mrm_files[1], "MRM_file.mzML", overwrite = TRUE)
} else if (length(mzml_files) > 0) {
    file.copy(mzml_files[1], "MRM_file.mzML", overwrite = TRUE)
} else {
    # Fallback: write a minimal mzML file with a chromatogram structure
    # This ensures the file exists and has the basic XML structure mzR expects for chromatograms
    mzml_content <- '<?xml version="1.0" encoding="utf-8"?>
<mzML xmlns="http://psi.hupo.org/ms/mzml" version="1.1.0">
  <cvList count="2">
    <cv id="MS" fullName="Proteomics Standards Initiative Mass Spectrometry Ontology" version="3.79.0" URI="http://psidev.cvs.sourceforge.net/*checkout*/psidev/psi/psi-ms/mzML/controlledVocabulary/psi-ms.obo"/>
    <cv id="UO" fullName="Unit Ontology" version="14:07:2009" URI="http://obo.cvs.sourceforge.net/*checkout*/obo/obo/ontology/phenotype/unit.obo"/>
  </cvList>
  <fileDescription>
    <fileContent>
      <cvParam cvRef="MS" accession="MS:1000584" name="mzML format"/>
    </fileContent>
  </fileDescription>
  <run id="run1">
    <chromatogramList count="1" defaultDataProcessingRef="dp1">
      <chromatogram id="tic" index="0">
        <cvParam cvRef="MS" accession="MS:1000235" name="total ion current chromatogram" value=""/>
        <binaryDataArrayList count="2">
          <binaryDataArray encodedLength="0">
            <cvParam cvRef="MS" accession="MS:1000595" name="time array" value=""/>
            <cvParam cvRef="MS" accession="MS:1000523" name="64-bit float" value=""/>
            <cvParam cvRef="MS" accession="MS:1000574" name="zlib compression" value=""/>
            <binary></binary>
          </binaryDataArray>
          <binaryDataArray encodedLength="0">
            <cvParam cvRef="MS" accession="MS:1000515" name="intensity array" value=""/>
            <cvParam cvRef="MS" accession="MS:1000523" name="64-bit float" value=""/>
            <cvParam cvRef="MS" accession="MS:1000574" name="zlib compression" value=""/>
            <binary></binary>
          </binaryDataArray>
        </binaryDataArrayList>
      </chromatogram>
    </chromatogramList>
  </run>
</mzML>'
    writeLines(mzml_content, "MRM_file.mzML")
}