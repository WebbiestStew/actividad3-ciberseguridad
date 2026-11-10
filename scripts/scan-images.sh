#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p evidence
docker_config=$(mktemp -d)
trap 'rm -rf "$docker_config"' EXIT
export DOCKER_CONFIG="$docker_config"
trivy --version
for major in 14 18; do
  trivy image --no-progress --image-src remote --platform linux/amd64 --scanners vuln \
    --format json --output "evidence/trivy-node${major}.json" "node:${major}"
done
python3 - <<'PY' | tee evidence/trivy-resumen.txt
import collections
import json

levels = ("CRITICAL", "HIGH", "MEDIUM", "LOW", "UNKNOWN")
print("Imagen\t" + "\t".join(levels))
for major in (14, 18):
    with open(f"evidence/trivy-node{major}.json") as report:
        data = json.load(report)
    counts = collections.Counter(
        vuln.get("Severity", "UNKNOWN")
        for result in data.get("Results", [])
        for vuln in result.get("Vulnerabilities") or []
    )
    print(f"node:{major}\t" + "\t".join(str(counts[level]) for level in levels))
    print("Digest:", ", ".join(data.get("Metadata", {}).get("RepoDigests") or []))
PY
