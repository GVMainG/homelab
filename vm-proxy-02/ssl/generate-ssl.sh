#!/usr/bin/env bash
# Генерирует корневой CA и wildcard-сертификат для *.home.loc
# Выходные файлы: ssl/certs/{ca.crt,ca.key,wildcard.home.loc.crt,wildcard.home.loc.key}
# Запускать из любого места — пути вычисляются относительно скрипта
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CERTS_DIR="${SCRIPT_DIR}/certs"
DOMAIN="home.loc"
DAYS=3650

for cmd in openssl; do
    command -v "$cmd" >/dev/null 2>&1 || {
        echo "ERROR: $cmd is required but not installed" >&2
        exit 1
    }
done

mkdir -p "${CERTS_DIR}"
cd "${CERTS_DIR}"

# ── Root CA ───────────────────────────────────────────────────────────────────
echo "[ssl] Generating Root CA..."
openssl genrsa -out ca.key 4096

openssl req -x509 -new -nodes \
    -key ca.key \
    -sha256 \
    -days "${DAYS}" \
    -out ca.crt \
    -subj "/C=RU/ST=Local/L=Local/O=Homelab CA/CN=Homelab Root CA (${DOMAIN})"

# ── Wildcard Certificate ──────────────────────────────────────────────────────
echo "[ssl] Generating wildcard certificate for *.${DOMAIN}..."
openssl genrsa -out "wildcard.${DOMAIN}.key" 2048

openssl req -new \
    -key "wildcard.${DOMAIN}.key" \
    -out "wildcard.${DOMAIN}.csr" \
    -subj "/C=RU/ST=Local/L=Local/O=Homelab/CN=*.${DOMAIN}"

cat > "wildcard.${DOMAIN}.ext" <<EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage=digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName=@alt_names

[alt_names]
DNS.1=*.${DOMAIN}
DNS.2=${DOMAIN}
EOF

openssl x509 -req \
    -in "wildcard.${DOMAIN}.csr" \
    -CA ca.crt \
    -CAkey ca.key \
    -CAcreateserial \
    -out "wildcard.${DOMAIN}.crt" \
    -days "${DAYS}" \
    -sha256 \
    -extfile "wildcard.${DOMAIN}.ext"

# ── Cleanup temp files ────────────────────────────────────────────────────────
rm -f "wildcard.${DOMAIN}.csr" "wildcard.${DOMAIN}.ext" ca.srl

echo ""
echo "[ssl] Done. Certificates:"
ls -la "${CERTS_DIR}"
echo ""
echo "Fingerprint (CA):"
openssl x509 -noout -fingerprint -sha256 -in ca.crt
