# Parse the output of `gpg --with-colons --list-keys` to determine the validity
# of the key assigned to the key_id variable.
#
# Exit status:
# - 0: key is valid
# - 2: key is in the keyring but is not valid
# - 3: key is not in the keyring and is not valid
#
# References:
# - /usr/share/doc/gnupg/DETAILS
#
BEGIN {
  FS = ":"
  key_id = toupper(key_id)
}

! s && $1 == "pub" && toupper(substr($5, length($5) - length(key_id) + 1)) == key_id {
  s = $2 ~ /^[fu]$/ ? 3 : 1
}

END {
  exit (3 - s)
}

