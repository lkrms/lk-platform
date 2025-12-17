# Logging

To simplify output logging, `lk-platform` provides functions that duplicate the
running script's standard output and error streams, redirect them to a
timestamped log file, and allow granular control over what is displayed on the
terminal vs. what is logged or discarded.

Non-printing characters, e.g. ANSI escape sequences and characters before
standalone carriage returns, are removed from output as it is logged.

## Functions

> [!TIP]
>
> Calling `lk_log_open` after processing command-line arguments is all that's
> required for most scripts.

- `lk_log_open`: Creates a log file for the running script if it doesn't already
  have one, writes a header to separate the current run from previous runs, and
  redirects output to the file.

  Ignored if:

  - `LK_NO_LOG` is non-empty
  - Output is already being logged (e.g. by a parent process)
  - Bash is not reading commands from a script file

- `lk_start_trace`: Same as `lk_log_open`, but for trace output.

  Ignored if:

  - `LK_NO_LOG` is non-empty
  - `set -x` is already enabled
  - `LK_DEBUG` is not `Y`
  - Bash is not reading commands from a script file

## Default output paths

Output logs are stored in `$LK_BASE/var/log/lk-platform`, using a naming
convention that creates one file per script per user:

```bash
${LK_LOG_BASENAME:-$(basename "${LK_LOG_CMDLINE[0]:-$0})"}-$EUID.log
```

> [!NOTE]
>
> If `$LK_BASE/var/log/lk-platform` isn't writable, `lk-platform` tries to
> create log files in the current user's home directory, then in `/tmp`.

Trace output is written to `/tmp`, using a naming convention that effectively
creates one file per run:

```bash
${LK_LOG_BASENAME:-$(basename "${LK_LOG_CMDLINE[0]:-$0})"}-$EUID.$(TZ=UTC date +%Y%m%d%H%M%S).log
```

## Overrides

Assign values to one or more of the following variables to override the default
behaviour of logging functions in `lk-platform`:

- `LK_LOG_CMDLINE[]`: replaces the command line for which output is being
  logged.
  - The name of the running script (`"$0"`) is combined with its arguments
    (`"$@"`) by default.
  - The basename of the command (`"${LK_LOG_CMDLINE[0]}"`) is used as the output
    log's file name, and the command line (`"${LK_LOG_CMDLINE[@]}"`) is written
    to the log file when logging starts.
- `LK_LOG_BASENAME`: replaces the output log's file name without changing the
  command line written when logging starts.
  - The basename of `${LK_LOG_CMDLINE[0]:-$0}` is used by default.
- `LK_LOG_FILE`: overrides the output log's pathname.
  - Must not resolve to a file in `$LK_BASE/var/log/lk-platform`.
- `LK_LOG_TRACE_FILE`: similar to `LK_LOG_FILE`, but for trace output.
- `LK_LOG_SECONDARY_FILE`: adds another pathname to receive logged output.
- `LK_NO_LOG`: output logging is suppressed if non-empty.

## Internal variables

- \_LK_LOG_FD
- \_LK_TTY_ERR_FD
- \_LK_TTY_OUT_FD
- \_LK_FD
- \_LK_FD_LOGGED
- \_LK_LOG_FILE
- \_LK_LOG_TTY_LAST
