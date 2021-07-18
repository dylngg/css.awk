#!/bin/bash
# Generates a mincss.sh program with the corresponding source AWK code embedded.
#
# Usage: ./generate_sh.sh
tokenizer="./tokcss.awk"
astizer="./astcss.awk"
minifier="./ast2mincss.awk"
target="./mincss.sh"

cat <<EOF > "$target"
#!/bin/bash
# Minifies the given CSS file. If no CSS file is given or a '-' is provided
# instead, CSS from stdin is used.
#
# Usage: ./mincss.sh [CSSFILE]
#     or ./mincss.sh -h|--help
function die() {
    echo "\$@" 1>&2
    exit 1
}
function usage() {
    echo "Usage: ./mincss.sh [CSSFILE]"
    exit
}

if [ "\$1" = "-h" ] || [ "\$1" = "--help" ]; then
    usage
fi

if [ "\$1" = "" ] || [ "\$1" = "-" ]; then
    file=/dev/stdin
else
    file="\$1"
fi

if ! [ -r "\$file" ]; then
    die "CSS file '\$file' does not exist."
fi

EOF

printf "%s -- '%s' \"\$1\" | " '/usr/bin/env gawk' "$(grep -v '^#!' "$tokenizer")" >> "$target"
printf "%s -- '%s' | " '/usr/bin/env gawk' "$(grep -v '^#!' "$astizer")" >> "$target"
printf "%s -- '%s'" '/usr/bin/env gawk' "$(grep -v '^#!' "$minifier")" >> "$target"
chmod +x "$target"
