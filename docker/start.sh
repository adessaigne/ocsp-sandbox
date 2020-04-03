#!/bin/bash

# Check if server name is properly configured
if [ -z "$SERVER_NAME" ]; then
    echo "SERVER_NAME environment variable is not configured"
    exit 1
fi

# Initialize if it's brand new
if [ ! -d /var/ocsp ]; then
    COUNTRY=FR
    ORGANIZATION=ACME
    ORGANIZATION_UNIT=CERT

    echo "Initializing..."
    mkdir -p /var/ocsp
    cd /var/ocsp || exit 1

    echo "  Configuring openssl"
    sed -i 's/^RANDFILE/#&/' /etc/ssl/openssl.cnf
    {
        echo "[ usr_cert ]"
        echo "authorityInfoAccess = OCSP;URI:http://$SERVER_NAME:9000"
        echo "[ req_OCSP ]"
        echo "basicConstraints = CA:FALSE"
        echo "keyUsage = nonRepudiation, digitalSignature, keyEncipherment"
        echo "extendedKeyUsage = OCSPSigning"
    } >> /etc/ssl/openssl.cnf

    {
        echo "[req]"
        echo "default_bits = 2048"
        echo "default_md = sha256"
        echo "req_extensions = req_ext"
        echo "distinguished_name = dn"
        echo "[ dn ]"
        echo "[ req_ext ]"
        echo "subjectAltName = @alt_names"
        echo "[alt_names]"
        echo "DNS.1 = $SERVER_NAME"
    } > req.cnf

    echo "  Creating CA"
    openssl genrsa -out rootCA.key 2048 2>/dev/null
    openssl req -new -x509 -days 365 -key rootCA.key -out rootCA.crt -subj "/CN=$SERVER_NAME/OU=$ORGANIZATION_UNIT/O=$ORGANIZATION/C=$COUNTRY" -config req.cnf

    echo "  Configuring OCSP server"
    openssl req -new -nodes -out ocspSigning.csr -keyout ocspSigning.key -subj "/CN=ocsp.$SERVER_NAME/OU=$ORGANIZATION_UNIT/O=$ORGANIZATION/C=$COUNTRY" -config req.cnf 2>/dev/null
    mkdir -p ./demoCA/newcerts
    touch ./demoCA/index.txt
    echo "unique_subject = no" > ./demoCA/index.txt.attr
    echo '01' > ./demoCA/serial
    openssl ca -batch -keyfile rootCA.key -cert rootCA.crt -in ocspSigning.csr -out ocspSigning.crt -policy policy_anything -extensions req_OCSP -config /etc/ssl/openssl.cnf 2>/dev/null

    echo "Initialization complete"
fi

echo "Starting OCSP server..."
cd /var/ocsp
until (openssl ocsp -index demoCA/index.txt -port 9000 -rsigner ocspSigning.crt -rkey ocspSigning.key -CA rootCA.crt -text -out log.txt); do
    echo "Restarting OCSP server..."
done
