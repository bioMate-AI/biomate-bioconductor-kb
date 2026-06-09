#!/bin/bash
# Ensure all AWS Batch nextflow Compute Environments use the LATEST
# Launch Template version. Audit by default; pass --apply to auto-update
# any CE that lags. Pass --quiet to suppress output when there's nothing
# to do (suitable for cron / startup hooks).
#
# Background: LT v9 had a broken aws-cli install that surfaces only when
# running pipelines whose task containers lack a built-in aws-cli (e.g.
# nf-core minimal biocontainers). v14+ has the fix. Multiple CEs have
# been left behind on older LT versions for 7+ weeks at a time because
# updating the LT does NOT propagate to CEs — each CE pins a version.
# See docs/20260607_BATCH_AMI_AWSCLI_NOT_SELF_CONTAINED.md.

set -e
REGION="${AWS_REGION:-us-west-2}"
MODE="audit"
QUIET=0
for arg in "$@"; do
    case "$arg" in
        --apply) MODE="apply" ;;
        --quiet) QUIET=1 ;;
    esac
done

LAGGING=0
APPLIED=0

CES=$(aws batch describe-compute-environments --region "$REGION" \
  --query "computeEnvironments[?contains(computeEnvironmentName, 'nextflow')].[computeEnvironmentName,computeResources.launchTemplate.launchTemplateId,computeResources.launchTemplate.version]" \
  --output text)

[ $QUIET -eq 0 ] && echo "=== Nextflow CE Launch-Template versions ==="

while read CE_NAME LT_ID LT_VER; do
    [ -z "$LT_ID" ] || [ "$LT_ID" = "None" ] && continue
    LATEST=$(aws ec2 describe-launch-templates --launch-template-ids "$LT_ID" --region "$REGION" \
        --query 'LaunchTemplates[0].LatestVersionNumber' --output text)
    if [ "$LT_VER" = "$LATEST" ]; then
        [ $QUIET -eq 0 ] && printf "  %-30s v%s ✅\n" "$CE_NAME" "$LT_VER"
    else
        LAGGING=$((LAGGING + 1))
        printf "  %-30s v%s → v%s ❌\n" "$CE_NAME" "$LT_VER" "$LATEST"
        if [ "$MODE" = "apply" ]; then
            aws batch update-compute-environment \
                --compute-environment "$CE_NAME" \
                --compute-resources "launchTemplate={launchTemplateId=$LT_ID,version=$LATEST}" \
                --region "$REGION" --output text --query 'computeEnvironmentName' > /dev/null
            APPLIED=$((APPLIED + 1))
            echo "    → upgraded $CE_NAME to LT v$LATEST"
        fi
    fi
done <<< "$CES"

# --- Second invariant: CEs must NOT include arm64 (Graviton) instance families.
# `instanceTypes: optimal` includes c6g/m6g/r6g/t4g (Graviton); x86_64 containers
# raise `exec format error` when Batch schedules them onto an arm64 worker.
# CLAUDE.md: "the docker should be run in x86". Verified 2026-06-09 on
# biomate-nextflow-ce-v2; ce-v2 was the only offender, leaving systems_biology
# task containers to fail intermittently.
ARM_FAMILIES_RE="optimal|c6g|m6g|r6g|t4g|c7g|m7g|r7g"
[ $QUIET -eq 0 ] && echo "=== Nextflow CE instance-type families (must be x86_64) ==="
aws batch describe-compute-environments --region "$REGION" \
    --query "computeEnvironments[?contains(computeEnvironmentName, 'nextflow') && computeResources.type=='EC2'].[computeEnvironmentName,computeResources.instanceTypes]" \
    --output json | python3 -c "
import json, sys, re
ARM = re.compile(r'$ARM_FAMILIES_RE')
ces = json.load(sys.stdin)
for name, its in ces:
    its_s = ','.join(its or [])
    bad = bool(ARM.search(its_s))
    if bad:
        print(f'BAD\t{name}\t{its_s}')
    else:
        print(f'OK\t{name}\t{its_s}')
" | while IFS=$'\t' read STATUS CE_NAME ITS; do
    if [ "$STATUS" = "BAD" ]; then
        LAGGING=$((LAGGING + 1))
        printf "  %-30s ARM-INCLUSIVE: %s ❌\n" "$CE_NAME" "$ITS"
        if [ "$MODE" = "apply" ]; then
            # Replace with x86-only set; conservative defaults span CPU + memory needs.
            aws batch update-compute-environment \
                --compute-environment "$CE_NAME" \
                --compute-resources 'instanceTypes=["m5","c5","r5","m5n","c5n","m6i","c6i","r6i"]' \
                --region "$REGION" --output text --query 'computeEnvironmentName' > /dev/null
            APPLIED=$((APPLIED + 1))
            echo "    → restricted $CE_NAME to x86_64 families"
        fi
    else
        [ $QUIET -eq 0 ] && printf "  %-30s %s ✅\n" "$CE_NAME" "$ITS"
    fi
done

if [ "$MODE" = "apply" ] && [ $APPLIED -gt 0 ]; then
    echo
    echo "Updated $APPLIED CE(s). New worker instances will pick up the new LT;"
    echo "existing idle workers will be replaced as Batch scales."
elif [ $LAGGING -gt 0 ] && [ "$MODE" != "apply" ]; then
    echo
    echo "$LAGGING CE(s) are behind. Re-run with --apply to auto-update."
    exit 1
fi
exit 0
