#!/usr/bin/env bash
# Generate frontend/config.js from Terraform outputs and serve the UI.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TF="$ROOT/terraform/phase4_rag_api"
BASE="$(terraform -chdir="$TF" output -raw api_base_url)"
KEY="$(terraform -chdir="$TF" output -raw rag_api_key_value)"

cat > "$ROOT/frontend/config.js" <<EOF
window.ENTERPRISE_RAG_CONFIG = {
  apiBaseUrl: "${BASE}",
  // API key is NOT embedded by default for safety.
  // Paste it in the UI (or set sessionStorage.rag_api_key).
};
EOF

echo "Wrote frontend/config.js with apiBaseUrl=${BASE}"
echo "API key id: $(terraform -chdir="$TF" output -raw rag_api_key_id)"
echo "Retrieve key: terraform -chdir=terraform/phase4_rag_api output -raw rag_api_key_value"
echo "Serving http://127.0.0.1:8080 ..."
cd "$ROOT/frontend"
python3 -m http.server 8080
