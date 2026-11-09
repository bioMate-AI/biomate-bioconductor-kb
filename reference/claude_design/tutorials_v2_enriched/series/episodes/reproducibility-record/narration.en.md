## Step 1 — Trace a result back to its run

A scientific result is easier to review when you can trace where it came from. BioMate provides a reproducibility record for a run. This lesson shows how to inspect that record, using our completed ADMET example, without assuming that every field is populated.

## Step 2 — Open the Reproducibility record

Open the Reproducibility record tab for the same completed run. Review the workflow identity, the parameters and the output references that are present. Keep the run identity connected to your downloaded files, especially when several runs produce similarly named outputs.

## Step 3 — A field can exist without a value

In the default record inspected for this example, input bindings are empty and output checksums are not populated. These are gaps to document, not details to fill in from memory. Do not describe this record as complete proof that anyone can reproduce the result.

## Step 4 — A checksum checks bytes

A checksum is a fingerprint of file contents. Matching checksums can help establish that two copies contain the same bytes. That is different from checking whether the model, inputs or interpretation are appropriate. This lesson does not claim that checksum computation has been demonstrated for the example.

## Step 5 — Hand over evidence with its limits

For a colleague or client, keep the run record with the original outputs and a short note describing missing information. Verify input identity, software versions and relevant parameters before making a reproducibility claim. The record helps organize that review; it does not replace it.
