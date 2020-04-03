#!/bin/bash

# Saves standard input to CSR temp file
CSR=$(tempfile)
cat > "$CSR"

# Extract DNS from CSR and save it in temp file
DNS=$(tempfile)
openssl req -noout -text -in "$CSR" | awk '/X509v3 Subject Alternative Name/ {getline;gsub(/ /, "", $0); print}' | tr -d "DNS:" > "$DNS"

# Move to OCSP folder as we store data in it
cd /var/ocsp

# Sign certificate
openssl ca -batch -days 365 -keyfile rootCA.key -cert rootCA.crt -policy policy_anything -notext -config <(
    cat /etc/ssl/openssl.cnf
    echo "[ usr_cert ]"
    echo "subjectAltName = @alt_names"
    echo "[ alt_names ]"
    echo "DNS.1 = $(cat "$DNS")"
) -infiles "$CSR"

# Restart openssl OCSP service
pkill -9 openssl

# Remove temp files
rm -f "$CSR" "$DNS"

