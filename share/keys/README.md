# Trusted keys

> [!TIP]
>
> You can use an [ephemeral GnuPG home directory][ephemeral] with the `gpg`
> commands below:
>
> ```bash
> GNUPGHOME=$(mktemp -d)
> export GNUPGHOME
> ```

## Downloading PPA keys

For example, to get the signing key for the `ondrej/php` PPA, pass the
fingerprint that appears under "Technical details about this PPA" on its
[Launchpad page][ppa] to the `gpg` command as follows:

```bash
fingerprint=B8DC7E53946656EFBCE4C1DD71DAEAAB4AD4CAB6

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
