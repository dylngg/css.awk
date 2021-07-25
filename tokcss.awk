#!/usr/bin/env awk -f
BEGIN {
    in_comment = ""
}
{
    delete tmpchars
    nchars = split($0, tmpchars, "")

    folded = ""
    for (i = 1; i <= nchars; i++) {
        can_peek = i + 1 <= nchars
        if (in_comment && can_peek && tmpchars[i] == "*" && tmpchars[i+1] == "/") {
            in_comment = ""
            print "*/"
            i++
            continue
        }
        if (!in_comment && can_peek && tmpchars[i] == "/" && tmpchars[i+1] == "*") {
            in_comment = "true"
            print "/*"
            i++
            continue
        }

        print tmpchars[i]
    }
    print ""
}
