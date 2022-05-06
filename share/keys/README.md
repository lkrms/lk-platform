# Trusted keys

## Downloading and exporting PGP keys

> Using an [ephemeral GnuPG home directory][ephemeral] is recommended:
>
> ```bash
> GNUPGHOME=$(mktemp -d)
> export GNUPGHOME
> ```

For example, to get the signing key for the `ondrej/php` PPA, pass the
fingerprint that appears under "Technical details about this PPA" on its
[Launchpad page][ppa] to the `gpg` command as follows:

```bash
fingerprint=14AA40EC0831756756D7F66C4F4EA0AAE5267A6C

# Add the signing key to your keyring
gpg --keyserver keyserver.ubuntu.com --recv-keys "$fingerprint"

# Option 1: export it as a binary OpenPGP file and check it
gpg --output ./ppa-ondrej-php.gpg --export "$fingerprint"
gpg ./ppa-ondrej-php.gpg

# Option 2: export it as an ASCII armoured text file and check it
gpg --output ./ppa-ondrej-php.asc --armor --export "$fingerprint"
gpg ./ppa-ondrej-php.asc
```

The key file can then be installed to `/etc/apt/trusted.gpg.d`.

[ppa]: https://launchpad.net/~ondrej/+archive/ubuntu/php
[ephemeral]:
    https://www.gnupg.org/documentation/manuals/gnupg/Ephemeral-home-directories.html
