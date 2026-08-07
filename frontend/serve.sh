#!/usr/bin/env bash
# Generate local frontend config from Terraform outputs and serve the UI.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TF="$ROOT/terraform/phase4_rag_api"
BASE="$(terraform -chdir="$TF" output -raw api_base_url)"
KEY="$(terraform -chdir="$TF" output -raw rag_api_key_value)"

# Public defaults (safe to commit) — no API key.
cat > "$ROOT/frontend/config.js" <<EOF
window.ENTERPRISE_RAG_CONFIG = {
  apiBaseUrl: "${BASE}",
};
EOF

# Local-only secrets file (gitignored). Auto-loads the API key in the UI.
cat > "$ROOT/frontend/config.local.js" <<EOF
window.ENTERPRISE_RAG_LOCAL_CONFIG = {
  apiBaseUrl: "${BASE}",
  apiKey: "${KEY}",
};
EOF

echo "Wrote frontend/config.js and frontend/config.local.js"
echo "API key is embedded for local use only (config.local.js is gitignored)."
echo "Serving http://127.0.0.1:8080 ..."
cd "$ROOT/frontend"
exec python3 -m http.server 8080 --bind 127.0.0.1
