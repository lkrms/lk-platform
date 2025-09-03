# `smb.conf` templates

Settings:

- `LK_SMB_CONF=('standalone'|'legacy')` (default: `standalone`)
- `LK_SMB_WORKGROUP=<workgroup>` (default: `WORKGROUP`)

## `standalone`.smb.t.conf

For standalone desktops, laptops and servers.

- Print services are completely disabled
- Interoperability with Windows, macOS and Linux clients is prioritised over
  support for Unix file modes and POSIX ACLs
- Home directories are shared but are not browseable

## `legacy`.smb.t.conf

Extends `standalone.smb.t.conf` with support for legacy clients.

- CIFS clients are allowed to connect
- `NTLMv1` authentication is enabled
