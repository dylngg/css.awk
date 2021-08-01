#!/bin/bash
source util.sh

print_ast=false
if [ "$1" = "--ast" ]; then
    print_ast=true
    shift
fi

cssfile="$(css_file_from_args "$@")"
echo "$cssfile" >&2
if $print_ast; then
     ../tokcss.awk "$cssfile" | ../astcss.awk | ../dedupastcss.awk
else
     ../tokcss.awk "$cssfile" | ../astcss.awk | ../dedupastcss.awk | ../ast2mincss.awk
     echo ""
fi
