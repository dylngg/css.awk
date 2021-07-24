#!/bin/bash
print_ast=false
if [ "$1" = "--ast" ]; then
    print_ast=true
    shift
fi

function random_css_file() {
    echo "$(find "$1" -type f -name '*.css' | shuf | head -1)"
}

if [ "$1" != "" ]; then
    if [ -d "$1" ]; then
        cssfile="$(random_css_file "$1")"
    elif [ -f "$1" ]; then
        cssfile="$1"
    else
        echo "$1: No such file or directory"
        exit 2
    fi
else
    cssfile="$(random_css_file .)"
fi

echo "$cssfile" >&2
if $print_ast; then
     ../tokcss.awk "$cssfile" | ../astcss.awk | ../ast2mincss.awk
     echo ""
else
     ../tokcss.awk "$cssfile" | ../astcss.awk
fi
