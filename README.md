# lk-platform

> Server and desktop provisioning scripts underpinned by a suite of portable
> Bash functions.

## Conventions

### Usage

There must be at least two spaces between a command-line option and its
definition.

```
What the command does, in one or two lines.

Usage:
  ${0##*/} [options] <ARG>...
  ${0##*/} [options] --exclude <ARG>...

Options:
  -f, --flag            A setting that can be enabled.
  -v, --value=<VALUE>   A value that can be set.

Environment:
  ENV_VARIABLE    Something different happens if this variable is in the
                  environment.

A further explanation of the command, possibly including example invocations.
```

### Bash 3.2 workarounds

Unless otherwise noted, Bash scripts in this project are written for **Bash 3.2
and above**. This is because they need to run on the only version of Bash
bundled with macOS since 2009.

Unfortunately, maintaining compatibility with Bash 3.2 means working around its
bugs and accepting the limitations that remain after polyfilling features added
in later versions.

If a script requires a more recent version of Bash than 3.2, it MUST fail during
input validation when running on an earlier version, e.g.

```bash
lk_bash_is 4 3 || lk_die "Bash 4.3 or higher required"
```

#### Parameter expansion

Bash 3.2 expands `"${@:2}"` as if it were `"$(IFS=" "; echo "${*:2}")"` unless
`IFS` contains a space. Workarounds include:

1. **Reset or unset `IFS`** (but changing `IFS` may cause side-effects)

   ```bash
   local IFS=$' \t\n'
   some_command "${@:2}"
   ```

   or

   ```bash
   local IFS
   unset IFS
   some_command "${@:2}"
   ```

2. **Use `shift` and `"$@"`** (preferred)

   ```bash
   local ARG=$1
   shift
   some_command "$@"
   ```

#### Array expansion

Similarly, on Bash 3.2, the code below incorrectly reports `"not equal"` because
`${PIPESTATUS[*]}` expands to `"0 1"`, even though `IFS` is empty.

```bash
(
    IFS=
    true | false || [[ ${PIPESTATUS[*]} == 01 ]]
) && echo "equal" || echo "not equal"
```

Workarounds:

1. **Double-quote `${PIPESTATUS[*]}`** (fixes the issue, but `shfmt` may remove
   the redundant double quotes)

   ```bash
   (
       IFS=
       true | false || [[ "${PIPESTATUS[*]}" == 01 ]]
   ) && echo "equal" || echo "not equal"
   ```

2. **Use `[` instead of `[[`** (more robust, but `[` tests are deprecated for
   project code)

   ```bash
   (
       IFS=
       true | false || [ "${PIPESTATUS[*]}" == 01 ]
   ) && echo "equal" || echo "not equal"
   ```

3. **Use `test` instead of `[[`** (preferred)

   ```bash
   (
       IFS=
       true | false || test "${PIPESTATUS[*]}" = 01
   ) && echo "equal" || echo "not equal"
   ```

### File descriptors

Use `lk_fd_next` if possible, otherwise file descriptors are conventionally used
as follows:

- 3: `_LK_FD`: output from `lk_tty_*` functions
- 4: `BASH_XTRACEFD`
- 5: \<reserved by Bash>
- 6: original stdout
- 7: original stderr
- 8: FIFO
- 9: lock file (passed to `flock -n`)
