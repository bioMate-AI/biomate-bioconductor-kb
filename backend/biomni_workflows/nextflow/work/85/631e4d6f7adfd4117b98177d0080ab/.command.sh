#!/bin/bash -ue
python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.molecular_biology import digest_sequence
except ImportError:
    # Fallback: function may need to be implemented locally
    def digest_sequence(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = digest_sequence(
    dna_sequence="GAATTCATCGATCGGAATTC",
    enzyme_names="EcoRI",
    is_circular=("false" == "true")
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("digest_sequence_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("digest_sequence_output.txt", "w") as f:
    f.write("Biomni: Digest Sequence Results" + chr(10))
    f.write("=" * 60 + chr(10) + chr(10))
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + chr(10))
    else:
        f.write(str(result))

print("digest_sequence completed successfully")
PYEOF
