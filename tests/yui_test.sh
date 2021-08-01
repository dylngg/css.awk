#!/bin/bash
source util.sh

cssfile="$(css_file_from_args "$@")"
echo "$cssfile" >&2
yuicompressor --type css "$cssfile"
