# Functions

If the following lists were complete, they would probably be useful for static
analysis.

## Command wrappers (functions that call a given command)

### `core`

- `lk_pass`
- `lk_test_all`
- `lk_test_any`
- `lk_elevate`
- `lk_sudo`
- `lk_run_as`
- `lk_unbuffer`
- `lk_mktemp_with`
- `lk_mktemp_dir_with`
- `lk_trap_add`
- `lk_tty_add_margin`
- `lk_tty_dump`
- `lk_tty_run`
- `lk_tty_run_detail`
- `lk_cache`
- `lk_log_run_tty_only`
- `lk_xargs`
- `lk_get_outputs_of`
- `lk_maybe_drop`
- `lk_nohup`

### `debian`

- `_lk_apt_flock`

### `git`

- `lk_git_with_repos`

### `provision`

- `lk_maybe_trace`

## Functions that operate on a given variable

- `lk_plural` (read-only)
- `lk_assign`
- `lk_is_true` (read-only)
- `lk_is_false` (read-only)
