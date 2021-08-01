#!/bin/bash
rand_css_file() {
    if [ "$1" = "" ]; then
        search_dir="."
    else
        search_dir="$1"
    fi

    echo "$(find "$search_dir" -type f -name '*.css' | shuf | head -1)"
}
css_file_from_args() {
    if [ "$1" != "" ]; then
        if [ -d "$1" ]; then
            cssfile="$(rand_css_file "$1")"
        elif [ -f "$1" ]; then
            cssfile="$1"
        else
            echo "$1: No such file or directory"
            exit 2
        fi
    else
        cssfile="$(rand_css_file)"
    fi
    echo "$cssfile"
}
