# Setup Passkit Environment variables

### `PASSKIT_WEB_SERVICE_HOST`

This is the host where your Rails app is running. It is used to generate the URLs for the passes. 
When the device wants to update the Pass, it will invoke services on this host.
In production, it will simply be your domain name, but in development you can use [ngrok](https://ngrok.com/) to expose your local server to the internet.

**Remember that it must always start with `https://`.**

### Apple intermediate certificate

This is the easy one.
Head to https://www.apple.com/certificateauthority/ and download the latest Apple Intermediate Certificate Worldwide Developer Relations.
Use the one that issued your pass certificate (its Issuer). You pass it to `Passkit::SigningMaterial`.

### `PASSKIT_APPLE_TEAM_IDENTIFIER`

You find this in your Apple Developer dashboard, under Membership.

![Membership](membership.png)

### `PASSKIT_PASS_TYPE_IDENTIFIER` and the pass certificate

Head to your Apple Developers console and generate a new certificate.

![Step 1](step1.png)

![Step 2](step2.png)

![Step 3](step3.png)

The identifier is the `PASSKIT_PASS_TYPE_IDENTIFIER` variable.

Now, create a certificate signing request: https://developer.apple.com/help/account/create-certificates/create-a-certificate-signing-request/

And create the certificate:

![Step 4](step4.png)

At the end, you'll have a `pass.cer` file.

Open it in the Keychain Access tool and export it (you must be in the My Certificates tab):

![Step 5](step5.png)

Set a password and get your p12 file. Build the signing material from it with
`Passkit::SigningMaterial.from_p12(File.binread(path), password, intermediate_certificate: ...)`
in `config.signing_material_resolver` (see the README).

`PKCS12_parse: unsupported`: you might encounter this issue: https://help.heroku.com/88GYDTB2/how-do-i-configure-openssl-to-allow-the-use-of-legacy-cryptographic-algorithms
