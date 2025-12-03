# Coding standards

> [!NOTE]
>
> The coding standards that follow are a work in progress. Some are more
> aspirational than others.

## Variable names

- Settings, environment values and global variables for general use: `LK_*`.
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
  `[[ $var =~ ^[+-]?[0-9]+$ ]]`, otherwise `BASH_REMATCH` must be `local`.

## Compatibility

- If code is not platform-specific, it must run on Linux, macOS and Windows.
- Code that can safely fail on outdated versions of Bash is allowed if it fails
  early on those versions (examples below). Otherwise, for compatibility with
  macOS, code must run on **Bash 3.2 and above**.
  ```shell
  # In a function
  lk_bash_is 4 || lk_err "Bash 4 or higher required" || return
  # In a script
  lk_bash_is 4 3 || lk_die "Bash 4.3 or higher required"
  ```
