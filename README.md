# OCSP sandbox

## Overview

This project is a sandbox for testing OCSP and OCSP stapling.
It's all in a docker image that you build on-the-fly.

Thanks to OCSP a client can know if the server certificate is revoked or not by asking an OCSP responder.
With OCSP stapling, the server itself asks the OCSP responder and add to its certificate a short-lived timestamped proof that the client can validate without asking the responder.

Note: Chrome and Chromium only support OCSP stapling and not OCSP as asking a 3rd party server if a certificate is valid is a privacy disclosure issue.

## Usage

You need to call the `ocsp.sh` script with one or many commands
```shell script
./ocsp.sh command [other_commands...]
```                                  

The commands are:
* `build` to build the docker image (named 'ocsp')
* `create` to create the docker container (named 'ocsp')
* `start` to start the 'ocsp' docker container
* `stop` to stop the 'ocsp' docker container
* `rm` to remove the 'ocsp' docker container
* `sign <file.csr> <file.crt>` to sign a certificate request and create a certificate
* `rootca <root.crt>` to write the root certificate
* `revoke <file.crt>` to revoke a certificate
* `check <root.crt> <file.crt>` to check the revocation status of a certificate

As this `ocsp.sh` script is just a wrapper you can also directly call the docker and openssl commands, see how in the script.

## Demo

In this demo we'll first generate certificates then we'll test OCSP and OCSP stapling with OpenSSL and finally test it in Java.

### Certificate generation

First, let's start OCSP docker image and retrieve the root certificate
```shell script
./ocsp.sh build create start rootca rootca.crt
```

Then generate a private key
```shell script
openssl genrsa -aes256 -out $(hostname).key 2048 
```

And a certificate request
```shell script
openssl req -new -key $(hostname).key -out $(hostname).csr -subj "/CN=$(hostname)/OU=CERT/O=ACME/C=FR" -config <(
cat <<-EOF
[req]
default_bits = 2048
default_md = sha256
req_extensions = req_ext
distinguished_name = dn
[ dn ]
[ req_ext ]
subjectAltName = @alt_names
[alt_names]
DNS.1 = $(hostname)
EOF
)
```

Now you can sign this request and get a certificate
```shell script
./ocsp.sh sign $(hostname).csr $(hostname).crt
``` 

You can check that this certificate is valid
```shell script
./ocsp.sh check rootca.crt $(hostname).crt
```

If you revoke it
```shell script
./ocsp.sh revoke $(hostname).crt
```                             

Then if you check it again it will be revoked
```shell script
./ocsp.sh check rootca.crt $(hostname).crt
```

### OpenSSL demo

To create a demo web server with OCSP Stapling
```shell script
openssl s_server -www -accept 8443 -status -key "$(hostname).key" -CAfile rootca.crt -cert "$(hostname).crt" 
```

You can also connect using OpenSSL
```shell script
 openssl s_client -connect "$(hostname):8443" -CAfile rootca.crt -status
```   

If OCSP stapling is correctly working you should see a section like
```text
OCSP Response Data:
    OCSP Response Status: successful (0x0)
    Response Type: Basic OCSP Response
    Version: 1 (0x0)
    Responder Id: C = FR, O = ACME, OU = CERT, CN = ocsp.server
    Produced At: Apr  3 12:01:29 2020 GMT
    Responses:
    Certificate ID:
      Hash Algorithm: sha1
      Issuer Name Hash: DBFE2F78C1DCCF9E6594DBB4D34336A224485EFA
      Issuer Key Hash: 6E40F4628D4B1B99FA82045BCA3B94F544E9C9E5
      Serial Number: 02
    Cert Status: revoked
    Revocation Time: Apr  1 18:58:00 2020 GMT
    This Update: Apr  3 12:01:29 2020 GMT
```  

If you want to use your own browser to test it then you need to trust the `rootca.crt` on your computer.
Afterwards it's strongly recommended to remove this trust :)

### Java demo

Requirement: OpenJDK 11 or later in your path to run single-file source-code programs

First let's create a PKCS12 **with the certificate chain**. If you don't have the certificate chain then OCSP stapling won't work on java
```shell script
openssl pkcs12 -export -inkey "$(hostname).key" -in "$(hostname).crt" -CAfile rootca.crt -chain -name "$(hostname)" -out "$(hostname).p12"
``` 

Then let's create a `Server.java` file
```java
import java.io.OutputStreamWriter;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import javax.net.ssl.SSLContext;
import com.sun.net.httpserver.HttpsConfigurator;
import com.sun.net.httpserver.HttpsServer;
import com.sun.net.httpserver.spi.HttpServerProvider;

public class Server {
    public static void main(String... args) throws Exception {
        // Configure using properties
        System.setProperty("javax.net.ssl.keyStore", InetAddress.getLocalHost().getHostName() + ".p12");
        System.setProperty("javax.net.ssl.keyStorePassword", "changeit");
        System.setProperty("jdk.tls.server.enableStatusRequestExtension", "true");

        // Basic HTTPS server
        HttpsServer server = HttpServerProvider.provider().createHttpsServer(new InetSocketAddress(8443), 0);
        server.setHttpsConfigurator(new HttpsConfigurator(SSLContext.getDefault()));
        server.createContext("/", exchange -> {
            exchange.sendResponseHeaders(200, 0);
            try (OutputStreamWriter writer = new OutputStreamWriter(exchange.getResponseBody())) {
                writer.write("Hello world! (requested URL is " + exchange.getRequestURI() + ")");
            }
        });
        server.start();
    }
}
```

Now you can  access your server in HTTPS on port 8443 and you'll see an error or not depending if your certificate is revoked.

If you want a Java client then you need to create the truststore
```shell script
keytool -import -alias rootca -file rootca.crt -keystore rootca.p12 -noprompt
```

Then create this `Client.java` file
```java
import java.net.InetAddress;
import java.net.URL;
import java.security.Security;

public class Client {
    public static void main(String... args) throws Exception {
        // Configure using properties
        System.setProperty("javax.net.ssl.trustStore", "rootca.p12");
        System.setProperty("javax.net.ssl.trustStorePassword", "changeit");
        System.setProperty("com.sun.net.ssl.checkRevocation", "true");
        System.setProperty("com.sun.security.enableCRLDP", "true");

        // This needs to be a "Security" property not a "System" one
        Security.setProperty("ocsp.enable", "true");

        new URL("https://" + InetAddress.getLocalHost().getHostName() + ":8443/" + String.join("/", args)).openStream().transferTo(System.out);
    }
}
``` 

To run this client simply type
```shell script 
java Client.java
```
