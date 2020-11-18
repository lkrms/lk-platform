/"https:\/\/github\.com\/lkrms\/lk-platform\.git"/ {
    found = 1
}
found && /([^\\]|^)$/ {
    print
    print "(cd \"/opt/${LK_PATH_PREFIX:-$PATH_PREFIX}platform\" &&"
    print "    _USER=$(stat --printf '%U' .) &&"
    print "    sudo -Hu \"$_USER\" git reset --hard " commit ")"
    found=0
    next
}
{    print
}
