#!/usr/bin/env bash

function input1() {
    cat <<'EOF'
"\"This is quoted,\" he said. \"That's correct,\" came the reply."
'This isn\'t quoted with double quotes, but with single quotes.'
~/$this/has a tilde-prefix/and/`unsafe characters`
~/Code/*/l[ka]*
~user1/.config/My App/*.json
"~user1/.config/My App/*.json"
~user1/.config/My\ App/*.json
'~user1/.config/My\ App/*.json'
~"user1"/.config/My\ App/*.json
~"user1"/.config/"My App"/*.json
"Bad escape\"
"Good escape\\"
~"Bad escape\"
~"Good escape\\"
~"Bad escape\"/.config
~"Good escape\\"/.config
'single'\''quote'
~'single'\''quote'
~'single'\''quote'/
''
""
~""/
~''/
EOF
}

function output1() {
    cat <<'EOF'
'"This is quoted," he said. "That'\''s correct," came the reply.'
'This isn'\''t quoted with double quotes, but with single quotes.'
~/'$this/has a tilde-prefix/and/`unsafe characters`'
~/'Code/'*'/l'[ka]*
~user1/'.config/My App/'*'.json'
~user1/'.config/My App/'*'.json'
~user1/'.config/My\ App/'*'.json'
~user1/'.config/My\ App/'*'.json'
~"user1"/'.config/My\ App/'*'.json'
~"user1"/'.config/"My App"/'*'.json'
'"Bad escape\"'
'Good escape\\'
~'"Bad escape\"'
~"Good escape\\"
~'"Bad escape\"/.config'
~"Good escape\\"/'.config'
''\''single'\''\'\'''\''quote'\'''
~'single'\''quote'
~'single'\''quote'/


~""/
~''/
EOF
}

assert_output_equals_file <(output1) \
    awk \
    -f "$(lk_awk_dir)/sh-sanitise-quoted-pathname.awk" \
    < <(input1)
