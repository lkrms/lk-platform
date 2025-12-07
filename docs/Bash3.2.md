# Bash 3.2 compatibility

Unless otherwise noted, Bash code in `lk-platform` is expected to run on **Bash
3.2 and above**. This is to maintain support for the only version of Bash
bundled with macOS since 2009.

Unfortunately, maintaining compatibility with Bash 3.2 means working around its
bugs and accepting the limitations that remain after polyfilling features added
in later versions.

Code that requires a more recent version of Bash must fail as early as possible
when running on an earlier version. Examples are given in the project's [coding
standards][compatibility].

## Parameter expansion

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

## Array expansion

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

[compatibility]: Standards.md#compatibility
