# Coding standards

> [!NOTE]
>
> This document is subject to ongoing review.
>
> New and refactored `lk-platform` code should comply with the following coding
> standards. Code committed before relevant standards were introduced may not be
> compliant.

## Variable names

- Settings, environment variables, and global variables for general use: `LK_*`.
- Variables for internal use only: `_LK_*`.
- Local variables in contexts where variables to act upon may be passed by name:
  `_<name>`.
- In new and refactored code, local variables should have `snake_case` names
  wherever possible.

## Arguments

- Variables passed by name must be validated, e.g. with `unset -v "$name"` or
  `declare -p "$name"`.
- Functions must fail with `lk_err`, `lk_bad_args` or `lk_usage` if called with
  missing/invalid arguments. They must not assume that mandatory arguments are
  always given.
- If possible, values should be tested with extglob patterns like
  `[[ $var == ?(+|-)+([0-9]) ]]` instead of regex like
  `[[ $var =~ ^[+-]?[0-9]+$ ]]`. Otherwise, `BASH_REMATCH` must be `local`.

## File descriptors

File descriptors used in `lk-platform` are as follows:

- 3: `_LK_FD`: output from `lk_tty_*` functions
- 4: `BASH_XTRACEFD`
- 5: \<reserved by Bash>
- 6: original stdout
- 7: original stderr
- 8: FIFO
- 9: lock file (passed to `flock -n`)

If none of these are appropriate, `lk_fd_next` should be used to safely identify
the next available file descriptor.

## Compatibility

- If code is not platform-specific, it must run on Linux, macOS and Windows.
- Code that can safely fail on outdated versions of Bash is allowed if it fails
  early on those versions (examples below). Otherwise, for compatibility with
  macOS, code must run on **Bash 3.2 and above**. Recommendations for achieving
  this are [provided separately][Bash 3.2].
  ```shell
  # In a function
  lk_bash_is 4 || lk_err "Bash 4 or higher required" || return
  # In a script
  lk_bash_is 4 3 || lk_die "Bash 4.3 or higher required"
  ```

## Documentation

### Usage

There must be at least two spaces between an option and its definition (in this
example, after `-v, --value=<value>` and before `A value that can be set.`).

```
What the command does, in one or two lines.

Usage:
  ${0##*/} [options] <arg>...
  ${0##*/} [options] --exclude <arg>...

Options:
  -f, --flag            A setting that can be enabled.
  -v, --value=<value>   A value that can be set.

Environment:
  ENV_VARIABLE    Something different happens if this variable is in the
                  environment.

A further explanation of the command, possibly including example invocations.
```

[Bash 3.2]: Bash3.2.md
