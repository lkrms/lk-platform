# lk-platform

Provisioning scripts and utilities for servers and desktops, underpinned by a
suite of portable Bash functions.

## Requirements

### Hosting servers

- Ubuntu LTS Server for amd64 or arm64
  - **Full support:** Ubuntu Server 24.04, 22.04 (recommended)
  - **Limited support:** Ubuntu Server 20.04, 18.04 (end of life)

> [!NOTE]
>
> The only version of PHP available for installation on a Ubuntu server after
> its [end of life date][ubuntu-releases] is the original release version:
>
> | Ubuntu version   | PHP version |
> | ---------------- | ----------- |
> | 24.04 ("noble")  | 8.3         |
> | 22.04 ("jammy")  | 8.1         |
> | 20.04 ("focal")  | 7.4         |
> | 18.04 ("bionic") | 7.2         |

### General servers

- Arch Linux
  - Same tooling as for desktops

### Desktops

- Arch Linux
- macOS
- Windows
  - Git Bash (bundled with [Git for Windows][git-for-windows]) or WSL
  - Provisioning is [implemented separately][win10-unattended]

## Installation

Packaging `lk-platform` for installation via `apt`, `homebrew`, `winget`, etc.
is a work in progress. For now, cloning the project's repository to
`/opt/lk-platform` or your home directory is recommended. For example:

```bash
git clone https://github.com/lkrms/lk-platform.git
sudo mv lk-platform /opt/
```

Then, to update it:

```bash
cd /opt/lk-platform
git pull --ff-only
```

### Entry points

#### `rc.sh`

To integrate `lk-platform` with Bash, add something like this to your
`~/.bashrc` file:

```bash
if [[ -r /opt/lk-platform/lib/bash/rc.sh ]]; then
    . /opt/lk-platform/lib/bash/rc.sh
fi

# Or, if you don't want completion features or the lk-platform prompt:
if [[ -r /opt/lk-platform/lib/bash/rc.sh ]]; then
    LK_COMPLETION=0 LK_PROMPT=0 . /opt/lk-platform/lib/bash/rc.sh
fi
```

When `rc.sh` is sourced:

- [Settings][] are loaded from `lk-platform.conf` files
- [env.sh][] is sourced and evaluated to:
  - normalise `PATH`
  - evaluate the output of `brew shellenv` if Homebrew is installed
  - set `SUDO_PROMPT`
  - set `LANG` if unset on macOS
- Bash functions relevant to the host are loaded from `core.sh` and other
  modules
- If running interactively:
  - Bash is configured to save unlimited command history, with timestamps
  - [bash-completion][] and other completion functions are sourced if available
  - `prompt.sh` is loaded and enabled

> [!WARNING]
>
> If Bash ever runs with `--norc`, your command history will be truncated to 500
> lines without timestamps. This can be avoided by setting `HISTFILE` to a
> custom value in your `~/.bashrc` file, for example:
>
> ```bash
> HISTFILE=~/.bash_history_main
> ```

[bash-completion]: https://github.com/scop/bash-completion
[env.sh]: src/lib/bash/env.sh
[git-for-windows]: https://gitforwindows.org/
[Settings]: docs/Settings.md
[ubuntu-releases]:
  https://documentation.ubuntu.com/project/release-team/list-of-releases/
[win10-unattended]: https://github.com/lkrms/win10-unattended/
