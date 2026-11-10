#!/usr/bin/env python3
"""Run on the verified dev host: preserve-digest registry copies, no IAM changes.

Uses the instance's existing ECR push role. A small official regctl image streams
registry blobs; task images are not unpacked into the host Docker image store.
Source images are never deleted. Conflicting destination tags fail closed.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time


def aws(*args):
    return json.loads(subprocess.check_output(["aws", *args, "--region", "us-west-2", "--output", "json",
                                              "--cli-connect-timeout", "5", "--cli-read-timeout", "20"],
                                             env=dict(os.environ, AWS_MAX_ATTEMPTS="2"), text=True, timeout=90))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("directory")
    args = parser.parse_args()
    work = Path(args.directory).resolve()
    if not str(work).startswith("/tmp/biomate-image-publish-"):
        raise ValueError("Not a dedicated publication directory")
    plan = json.loads((work / "plan.json").read_text())
    if aws("sts", "get-caller-identity")["Account"] != "399683337364":
        raise ValueError("Wrong AWS account")
    registry = "399683337364.dkr.ecr.us-west-2.amazonaws.com"
    authdir = Path(tempfile.mkdtemp(prefix="auth-", dir=work))
    authfile = authdir / "config.json"
    # Official client digest recorded by the first verified dev-host pull.
    client_image = "ghcr.io/regclient/regctl@sha256:45b57933c2b67bb1e280b4baaa220ef1ab212c81268ab19589fa1e83719c7c82"
    subprocess.run(["docker", "pull", client_image], check=True, timeout=180)
    (work / "client-image.txt").write_text(client_image + "\n")
    # The trusted registry client needs to read its own root-owned 0600 token.
    # Keep it read-only/capability-free; this is not a scientific task container.
    command = ["docker", "run", "--rm", "--user", "0:0", "--network", "host", "--read-only", "--cap-drop", "ALL",
               "--security-opt", "no-new-privileges", "--memory", "512m", "--cpus", "1",
               "--tmpfs", "/tmp:rw,nosuid,nodev,size=64m", "-e", "HOME=/config",
               "-v", str(authdir) + ":/config/.docker:ro", client_image]
    records = []
    try:
        token = aws("ecr", "get-authorization-token")["authorizationData"][0]["authorizationToken"]
        descriptor = os.open(authfile, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, "w") as output:
            json.dump({"auths": {registry: {"auth": token}}}, output)
        for image in plan["images"]:
            source = registry + "/" + image["source_repository"] + "@" + image["digest"]
            tags = image["tags"]
            references = [":" + tag for tag in tags] or ["@" + image["digest"]]
            for reference in references:
                target = registry + "/" + image["target_repository"] + reference
                if tags:
                    existing = aws("ecr", "batch-get-image", "--repository-name", image["target_repository"],
                                   "--image-ids", "imageTag=" + reference[1:])
                    for found in existing.get("images", []):
                        if found["imageId"]["imageDigest"] != image["digest"]:
                            raise RuntimeError("Refusing conflicting destination: " + target)
                started = time.time()
                result = subprocess.run(command + ["image", "copy", "--referrers", "--digest-tags", source, target],
                                        capture_output=True, text=True, timeout=1800)
                record = {"source": source, "target": target, "exit_code": result.returncode,
                          "duration_s": round(time.time() - started, 3), "stdout": result.stdout,
                          "stderr": result.stderr}
                if result.returncode == 0:
                    actual = subprocess.check_output(command + ["image", "digest", target], text=True).strip()
                    record["verified_digest"] = actual
                    if actual != image["digest"]:
                        record["error"] = "digest mismatch"
                records.append(record)
                with (work / "results.jsonl").open("a") as out:
                    out.write(json.dumps(record) + "\n")
                print(json.dumps({k: record[k] for k in ("target", "exit_code", "duration_s")}), flush=True)
                if result.returncode or record.get("error"):
                    raise RuntimeError("Image copy failed; read exact results.jsonl record")
    finally:
        # Remove only the short-lived credential file created by this process.
        authfile.unlink(missing_ok=True)
    (work / "complete.json").write_text(json.dumps({"status": "copied_and_digest_verified", "records": len(records),
                                                  "images": len(plan["images"]), "client_image": client_image}) + "\n")


if __name__ == "__main__":
    main()
