#!/bin/bash

cd /var/ocsp
openssl ca -batch -keyfile rootCA.key -cert rootCA.crt -config /etc/ssl/openssl.cnf -revoke <(cat)
pkill -9 openssl
