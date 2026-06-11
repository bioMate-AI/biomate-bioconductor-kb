library(PSMatch)

# The workflow expects an input file named 'idf.mzid'
# We will try to find a real .mzid file from installed packages (PSMatch or msdata)
# If not found, we will create a minimal valid .mzid file.

mzid_files <- list.files(system.file("extdata", package = "PSMatch"), pattern = "\\.mzid$", recursive = TRUE, full.names = TRUE)

if (length(mzid_files) == 0 && requireNamespace("msdata", quietly = TRUE)) {
    mzid_files <- list.files(system.file("extdata", package = "msdata"), pattern = "\\.mzid$", recursive = TRUE, full.names = TRUE)
}

if (length(mzid_files) > 0) {
    file.copy(mzid_files[1], "idf.mzid", overwrite = TRUE)
} else {
    # Fallback to a minimal synthetic .mzid file
    fallback_mzid <- '<?xml version="1.0" encoding="UTF-8"?>
<MzIdentML id="123" version="1.1.0" xmlns="http://psidev.info/psi/pi/mzIdentML/1.1" creationDate="2021-01-01T00:00:00">
    <cvList>
        <cv id="MS" fullName="Proteomics Standards Initiative Mass Spectrometry Ontology" uri="https://raw.githubusercontent.com/HUPO-PSI/psi-ms-CV/master/psi-ms.obo" version="4.1.130"/>
    </cvList>
    <AnalysisSoftwareList>
        <AnalysisSoftware id="AS1" name="MS-GF+" version="Beta (v10072)">
            <SoftwareName>
                <cvParam cvRef="MS" accession="MS:1002048" name="MS-GF+"/>
            </SoftwareName>
        </AnalysisSoftware>
    </AnalysisSoftwareList>
    <SequenceCollection>
        <DBSequence id="DBSeq1" accession="P12345" searchDatabase_ref="SDB1"/>
        <Peptide id="Pep1">
            <PeptideSequence>SCALITDGR</PeptideSequence>
        </Peptide>
        <PeptideEvidence id="PE1" dbSequence_ref="DBSeq1" peptide_ref="Pep1" start="1" end="9" pre="K" post="R" isDecoy="false"/>
    </SequenceCollection>
    <AnalysisCollection>
        <SpectrumIdentification spectrumIdentificationList_ref="SIL1" spectrumIdentificationProtocol_ref="SIP1" id="SI1">
            <InputSpectra spectraData_ref="SD1"/>
            <SearchDatabaseRef searchDatabase_ref="SDB1"/>
        </SpectrumIdentification>
    </AnalysisCollection>
    <AnalysisProtocolCollection>
        <SpectrumIdentificationProtocol id="SIP1" analysisSoftware_ref="AS1">
            <SearchType>
                <cvParam cvRef="MS" accession="MS:1001083" name="ms-ms search"/>
            </SearchType>
            <Threshold>
                <cvParam cvRef="MS" accession="MS:1001494" name="no threshold"/>
            </Threshold>
        </SpectrumIdentificationProtocol>
    </AnalysisProtocolCollection>
    <DataCollection>
        <Inputs>
            <SearchDatabase id="SDB1" location="dummy.fasta">
                <DatabaseName>
                    <userParam name="dummy"/>
                </DatabaseName>
            </SearchDatabase>
            <SpectraData id="SD1" location="dummy.mzML">
                <SpectrumIDFormat>
                    <cvParam cvRef="MS" accession="MS:1000768" name="Thermo nativeID format"/>
                </SpectrumIDFormat>
            </SpectraData>
        </Inputs>
        <AnalysisData>
            <SpectrumIdentificationList id="SIL1">
                <SpectrumIdentificationResult id="SIR1" spectrumID="controllerType=0 controllerNumber=1 scan=1158" spectraData_ref="SD1">
                    <SpectrumIdentificationItem id="SII1" chargeState="2" experimentalMassToCharge="400.5" calculatedMassToCharge="400.5" peptide_ref="Pep1" rank="1" passThreshold="true">
                        <PeptideEvidenceRef peptideEvidence_ref="PE1"/>
                        <cvParam cvRef="MS" accession="MS:1002046" name="MS-GF:EValue" value="1.0E-10"/>
                    </SpectrumIdentificationItem>
                </SpectrumIdentificationResult>
            </SpectrumIdentificationList>
        </AnalysisData>
    </DataCollection>
</MzIdentML>'
    writeLines(fallback_mzid, "idf.mzid")
}

# Verify the file exists
stopifnot(file.exists("idf.mzid"))