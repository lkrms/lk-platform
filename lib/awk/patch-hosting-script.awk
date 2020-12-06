/"https:\/\/github\.com\/lkrms\/lk-platform\.git"/ {
    found = 1
}
found && /([^\\]|^)$/ {
    print
    print "({ cd \"/opt/${LK_PATH_PREFIX:-$PATH_PREFIX}platform\" 2>/dev/null ||"
    print "    cd /opt/lk-platform; } &&"
    print "    _USER=$(stat --printf '%U' .) &&"
    print "    sudo -Hu \"$_USER\" bash -c 'git reset --hard " commit " &&"
    print "    git remote set-url origin \"$PWD\"')"
    found=0
    next
}
{    print
}
