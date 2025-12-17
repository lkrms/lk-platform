# Coding standards

> [!NOTE]
>
> - This document is subject to ongoing review.
> - New and refactored `lk-platform` code should comply with the standards
>   below.
> - Code committed before relevant standards were introduced may not be
>   compliant until a subsequent review.

## Variable names

- [Settings][], environment variables, and global variables for general use:
  `LK_*`.
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
  macOS, code must run on Bash 3.2 and above. Recommendations for achieving this
  are [provided separately][Bash 3.2].
  ```bash
  # In a function
  lk_bash_is 4 || lk_err "Bash 4 or higher required" || return
  # In a script
  lk_bash_is 4 3 || lk_die "Bash 4.3 or higher required"
  ```

## Documentation

- [Rewrap][]-friendly Markdown must be used in comments and text files.
- Documentation other than synopses should be wrapped to 80 columns, including
  any delimiters. If a synopsis is significantly wider than 80 columns, options
  may be collapsed to `[options]` as in the example under [Usage](#usage) below.
- Complete sentences should be terminated with a full stop ('.').

### Functions

- A blank line is required between text and preformatted blocks, e.g. after
  `Options:` in the next example.

#### One signature

```bash
# lk_file [-i <regex>] [-dpbsrvq] [-m <mode>] [-o <user>] [-g <group>] <file>
#
# What the function does, in one or two lines.
#
# Options:
#
#     -i <regex>  Exclude lines that match a regular expression from comparison.
#     -d          Print a diff before replacing the file.
#     -p          Prompt to confirm changes (implies -d).
#     -b          Create a backup of the file before replacing it.
#     -s          Create the backup in a secure store (implies -b).
#     -r          Preserve the original file as `<file>.orig`.
#     -m <mode>   Specify a numeric mode for the file.
#     -o <user>   Specify an owner for the file.
#     -g <group>  Specify a group for the file.
#     -v          Be verbose (repeat for more detail; overrides previous -q).
#     -q          Only report errors (overrides previous -v).
#
# A further explanation of the function, possibly including its options, output,
# and return values.
#
# - If the function has a significant number of options, they may be listed as
#   above, but this is not a requirement.
# - Documentation may be written in point form if appropriate.
```

#### Multiple signatures

```bash
# - lk_trap_add [-f] <signal> <command> [<arg>...]
# - lk_trap_add -q [-f] <signal> "<command> [<arg>...]"
#
# This function can be called with a quoted or unquoted command.
#
# If -q is given, it must be the first argument, and the command should be
# quoted by passing it with any arguments to `lk_quote_args` or similar.
```

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
[Rewrap]: https://github.com/stkb/Rewrap
[Settings]: Settings.md
