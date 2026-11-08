#!/usr/bin/env python3
"""Prepare additive neutral ECR repositories and a frozen copy plan.

Never modifies/deletes a source image, changes IAM or registry settings, or
overwrites a destination repository. Existing destinations require a matching
migration tag from this task. --apply is required for repository creation.
"""
import argparse
import datetime
import json
from pathlib import Path

import boto3

ROOT = Path(__file__).resolve().parents[2]
AUDIT = ROOT / "docs/qa/20261107-image-name-migration"
MAPPING = json.loads((Path(__file__).parent / "image_name_map.json").read_text())


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    session = boto3.Session(profile_name="default")
    if session.client("sts", region_name="us-west-2").get_caller_identity()["Account"] != "399683337364":
        raise RuntimeError("Wrong AWS account")
    client = session.client("ecr", region_name="us-west-2")
    inventory = {r["repositoryName"]: r for p in client.get_paginator("describe_repositories").paginate() for r in p["repositories"]}
    plan = {"created_at": datetime.datetime.now(datetime.timezone.utc).isoformat(), "repositories": [], "images": [], "apply": args.apply}
    for source_name, source in sorted(inventory.items()):
        component = source_name.rsplit("/", 1)[-1]
        if component not in MAPPING:
            continue
        target_name = source_name[:-len(component)] + MAPPING[component]
        record = {"source": source_name, "target": target_name, "status": "planned"}
        if target_name in inventory:
            tags = client.list_tags_for_resource(resourceArn=inventory[target_name]["repositoryArn"])["tags"]
            if {t["Key"]: t["Value"] for t in tags}.get("BioMateImageNameMigration") != source_name:
                raise RuntimeError("Unowned destination collision: " + target_name)
            record["status"] = "existing_owned_destination"
        elif args.apply:
            result = client.create_repository(repositoryName=target_name,
                       imageTagMutability=source["imageTagMutability"],
                       imageScanningConfiguration=source.get("imageScanningConfiguration", {"scanOnPush": False}),
                       encryptionConfiguration=source["encryptionConfiguration"],
                       tags=[{"Key": "BioMateImageNameMigration", "Value": source_name}])
            record["status"] = "created_private_destination"
            record["arn"] = result["repository"]["repositoryArn"]
        plan["repositories"].append(record)
        for page in client.get_paginator("describe_images").paginate(repositoryName=source_name):
            for image in page["imageDetails"]:
                tags = image.get("imageTags", [])
                if any("biomni" in tag.lower() for tag in tags):
                    raise RuntimeError("Unexpected legacy image tag; requires explicit mapping")
                plan["images"].append({"source_repository": source_name, "target_repository": target_name,
                                       "digest": image["imageDigest"], "tags": tags,
                                       "size_bytes": image.get("imageSizeInBytes"),
                                       "media_type": image.get("imageManifestMediaType")})
        (AUDIT / "registry-plan.json").write_text(json.dumps(plan, indent=2) + "\n")
    print(json.dumps({"repositories": len(plan["repositories"]), "images": len(plan["images"]),
                      "tag_references": sum(len(i["tags"]) for i in plan["images"]), "apply": args.apply}))


if __name__ == "__main__":
    main()
