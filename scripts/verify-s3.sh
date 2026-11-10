#!/usr/bin/env bash
set -euo pipefail
export AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_EC2_METADATA_DISABLED=true
unset AWS_PROFILE AWS_DEFAULT_PROFILE AWS_SESSION_TOKEN AWS_SECURITY_TOKEN
bucket=actividad3-seguro-local
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT
local_aws() {
  aws --endpoint-url http://localhost:4566 --region us-east-1 --no-cli-pager --output json "$@"
}
local_aws s3api list-buckets
encryption=$(local_aws s3api get-bucket-encryption --bucket "$bucket")
printf '%s\n' "$encryption"
python3 -c 'import json,sys; rules=json.load(sys.stdin)["ServerSideEncryptionConfiguration"]["Rules"]; assert any(r["ApplyServerSideEncryptionByDefault"]["SSEAlgorithm"] == "AES256" for r in rules)' <<<"$encryption"
block=$(local_aws s3api get-public-access-block --bucket "$bucket")
printf '%s\n' "$block"
python3 -c 'import json,sys; c=json.load(sys.stdin)["PublicAccessBlockConfiguration"]; assert all(c[k] is True for k in ("BlockPublicAcls", "IgnorePublicAcls", "BlockPublicPolicy", "RestrictPublicBuckets"))' <<<"$block"
printf 'Archivo de prueba sin datos sensibles.\n' > "$workdir/prueba.txt"
local_aws s3api put-object --bucket "$bucket" --key prueba.txt --body "$workdir/prueba.txt"
objects=$(local_aws s3api list-objects-v2 --bucket "$bucket" --prefix prueba.txt)
printf '%s\n' "$objects"
python3 -c 'import json,sys; assert any(obj["Key"] == "prueba.txt" for obj in json.load(sys.stdin).get("Contents", []))' <<<"$objects"
if result=$(local_aws s3api get-object --no-sign-request --bucket "$bucket" --key prueba.txt "$workdir/anonimo.txt" 2>&1); then
  printf 'Acceso anónimo permitido por el simulador.\n%s\n' "$result"
  cmp "$workdir/prueba.txt" "$workdir/anonimo.txt"
elif [[ "$result" == *AccessDenied* || "$result" == *Forbidden* ]]; then
  printf 'Acceso anónimo denegado.\n%s\n' "$result"
else
  printf 'Prueba anónima inconclusa.\n%s\n' "$result" >&2
  exit 1
fi
if result=$(local_aws s3api get-bucket-policy-status --bucket "$bucket" 2>&1); then
  printf '%s\n' "$result"
else
  if [[ "$result" == *InternalFailure* && "$result" == *"not included within your LocalStack license"* ]]; then
    printf 'GetBucketPolicyStatus no está disponible con esta licencia de LocalStack.\n%s\n' "$result"
    if result=$(local_aws s3api get-bucket-policy --bucket "$bucket" 2>&1); then
      printf '%s\n' "$result"
      exit 0
    fi
  fi
  if [[ "$result" == *NoSuchBucketPolicy* ]]; then
    printf '%s\nNoSuchBucketPolicy indica que el bucket no tiene una política adjunta.\n' "$result"
  else
    printf '%s\n' "$result" >&2
    exit 1
  fi
fi
