#!/usr/bin/env gawk -f
# Given newline seperated characters in stdin from ./tokcss.awk, outputs a CSS
# AST of some sorts. The ast is of the form
#
# \t+TOKEN string...
#
# where the number of tab indentation is based on the number of selectors the
# TOKEN is in. e.g. RULE and VALUE tokens always has at least 1 indentation,
# since they exist in a selector. For example,
#
# .selector {
#     foo: bar1, bar2;
# }
#
# is outputted as:
#
# SELECTOR .selector
#       RULE foo
#               VALUE bar1
#               VALUE bar2
#
# Note that the tokens outputed are not the tokens specified in the CSS spec
# (https://www.w3.org/TR/CSS22/grammar.html), but rather a simplified token
# set.
#
# Also note for development purposes this program avoids single quotes to
# allow for easy embedding in shell scripts.
#
# Requires GNU awk (gawk) unfortunately.
#
# GPLv3 licensed since I borrowed code from GNUs AWK manual.
#
# Usage: gawk -f tokcss.awk CSSFILE | gawk -f astcss.awk

BEGIN {
    # Internal contexts:
    #
    # 1|  @media (keyrule: value) {
    #  |         ^ ~~~~~~~~~~~~ ^
    #  |              paren
    #  |       ^                ^ ^
    #  |       spaces           spaces
    #  |                          lspaces
    #  |  ^ ~~~~~~~~~~~~~~~~~~~~~ ^
    #  |        at
    #
    # 2|         .selector1 {
    #  |         ^ ~~~~~~ ^
    #  |          selector
    #  |  ^ ~~~~ ^        ^ ^
    #  |  lspaces         spaces
    #  |                    lspaces
    #
    # 3|                  rule1:       "a long value1",      alongvalue2;
    #  |                  ^ ~~ ^       ^ ~~~~~~~~~~~ ^       ^ ~~~~~~~ ^
    #  |                   rule             quote               value
    #  |  ^ ~~~~~~~~~~~~~ ^    ^ ~~~~~ ^             ^ ~~~~~ ^          ^
    #  |       lspaces          lspaces               lspaces           lspaces
    #
    # 4|         }
    #  |  ^ ~~~~ ^
    #  |  lspaces
    #  |         ^ lspaces
    #
    # 3|  }
    #  |  ^
    #  |  lspaces,
    #  |  ^ ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~^
    #  |                              global
    #
    # List of contexts:
    # global    The top-level parent context
    # selector  Any target(s) preceeding a "{"
    # at        @media, @namespace, etc...
    # paren     Parentheseis, used for keeping whitespace in selector
    # quote     Quoted section
    # rule      A "rule: value(s)" pair
    # value     A value corresponding to a rule.
    # lspaces   Leading whitespace
    # spaces    Whitespace
    awkcode = retrieve_awkcode()

    # Indentation can be given via -v INDENATION=...; this is for how many
    # indentations the outputted tokens should start at, NOT how many spaces
    # per indent to output (INDENTATION is used in respawn())
    if (INDENTATION != 0)
        indentation = INDENTATION
    else
        indentation = 0

    # Context stack can be given via -v CONTEXT_STACK=context:context:...
    if (CONTEXT_STACK != "") {
        split(CONTEXT_STACK, context_stack, ":")
        esp = length(context_stack) - 1
    }
    else {
        esp = 0
        context_stack[esp] = "global"
    }
    spool = ""

    # Comments are tricky in that we cant emit the entire spool when
    # emiting a COMMENT token since comments can appear anywhere. e.g.
    #
    # foo: bar /* hey */;
    #
    # and we dont want previous parts of the spool counted as comments.
    # Use spool_start to track where this cutoff is.
    spool_start = 1
}
# tok_chars Returns a new input string where each character is on its own
#           line.
function tok_chars(input) {
    delete tmpchars
    nchars = split(input, tmpchars, "")

    folded = ""
    for (i = 1; i <= nchars; i++) {
        can_peek = i + 1 <= nchars
        if (in_comment && can_peek && tmpchars[i] == "*" && tmpchars[i+1] == "/") {
            in_comment = ""
            folded = folded "*/" "\n"
            i++
            continue
        }
        if (!in_comment && can_peek && tmpchars[i] == "/" && tmpchars[i+1] == "*") {
            in_comment = "true"
            folded = folded "/*" "\n"
            i++
            continue
        }
        folded = folded tmpchars[i] "\n"
    }
    return folded "\n"
}
# retrieve_awkcode Returns the code of this awk file
function retrieve_awkcode() {
    # Note: PROCINFO is gawk exclusive

    # Try looking for -f/--file flag first, assuming there is only one file
    expect_f_flag = ""
    for (i = 0; i < length(PROCINFO["argv"]); i++) {
        arg = PROCINFO["argv"][i]
        if (expect_f_flag)
            return read(arg)
        else if (arg == "-f" || arg == "--file")
            expect_f_flag = "true"
    }

    # Assume its embedded in argv, but there may exist flags before it. Flags
    # may or may not have values, so look for --
    found_end_of_opts = ""
    for (i = 0; i < length(PROCINFO["argv"]); i++) {
        arg = PROCINFO["argv"][i]
        if (found_end_of_opts)
            return arg  # found the code!
        else if (arg == "--") {
            found_end_of_opts = "true"
            continue
        }
    }
    print "Please use \"-- PROGRAM\" or \"-f FILE\"" > "/dev/stderr"
    exit 2
}
# read Returns the contents of a file. Copied from:
#      https://www.gnu.org/software/gawk/manual/html_node/Readfile-Function.html
function read(filepath) {
    save_rs = RS
    RS = "^$"  # will never match if file has contents
    getline contents < filepath
    close(filepath)
    RS = save_rs
    return contents
}
# respawn Spawns a new awk program with the given input.
function respawn(input) {
    # FIXME: This is a necessary evil because parsing @media or @namespace is
    #        ambiguous and requires backtracking...

    # Save our context stack
    context_stack_str = ""
    for (ebp = 0; ebp <= esp; ebp++) {
        if (ebp != 0 || ebp != esp)
            context_stack_str = context_stack_str ":"
        context_stack_str = context_stack_str context_stack[ebp]
    }

    # We avoid single quotes in this file to allow us to wrap this file in
    # single quotes, but the problem then is that we now have single quotes in
    # our code! Turns out awk has a \xASCII to save us: (27 is a single quote)
    self = "gawk -v DEBUG=" DEBUG " -v INDENTATION=" indentation " -v CONTEXT_STACK=" context_stack_str " -- " shell_quote(awkcode)
    print input | self
    close(self)
}
# shell_quote Quotes the given string so that it can be passed to a shell.
#             Modified from
#             https://www.gnu.org/software/gawk/manual/html_node/Shell-Quoting.html
function shell_quote(s, single, qsingle, i, X, n, ret) {
    if (s == "")
        return "\"\""

    single = "\x27"  # single quote
    qsingle = "\"\x27\""
    n = split(s, X, single)

    ret = single X[1] single
    for (i = 2; i <= n; i++)
        ret = ret qsingle single X[i] single

    return ret
}
# context The top of the context stack (the current context)
function context() {
    return context_stack[esp]
}
# prev_context The next-to-top of the context stack (the previous context)
function prev_context() {
    return context_stack[esp-1 ]
}
# debug_line Prints out a useful line for debugging
function debug_line(for_ch) {
    if (DEBUG != "true")
        return

    printf "%s\t[", for_ch
    for (ebp = 0; ebp <= esp; ebp++) {
        if (ebp != 0)
            printf " "
        printf "%s", context_stack[ebp]
    }
    print "]: :" spool ":"
}
# push_context Adds a new context to the stack
function push_context(new_context) {
    esp += 1
    context_stack[esp] = new_context
}
# pop_context Pops the top context from the stack
function pop_context() {
    esp -= 1
}
# change_context Forcibly changes the current context.
function change_context(new_context) {
    context_stack[esp] = new_context
}
# in_blob_context Whether characters in this context should be ignored.
function in_blob_context() {
    return context() == "comment" || context() == "quote"
}
# in_block_context Whether the current context is a block. e.g. in { ... }
function in_block_context() {
    return context() == "global" || context() == "nested_statements"
}
# spool_emit_token Spits out a token with the current spool and resets it
function spool_emit_token(token) {
    for (i = 0; i < indentation; i++)
        printf "\t"

    print token " " spool
    spool = ""
}
# emit_token Spits out a token with the given spool without touching the
#            global spool
function emit_token(token, with_spool) {
    for (i = 0; i < indentation; i++)
        printf "\t"

    print token " " with_spool
}
# spool_last Returns the last character in the spool
function spool_last() {
    return substr(spool, length(spool), 1)
}
# spool_second_to_last Returns the second to last character in the spool
function spool_second_to_last() {
    return substr(spool, length(spool)-1, 1)
}
# spool_before Returns all characters before the given end (1-based index) of the spool.
function spool_before(end) {
    return substr(spool, 1, end)
}
# pop_spacing_context_if_found Shared actions for non-whitespace based actions.
function pop_spacing_context_if_found(with_char) {
    # at a non-whitespace character, pop spacing context
    if (context() == "lspaces")
        pop_context()
}
# resolve_ruleset_or_nested_statements_ambiguity_as_rule
#       Resolves the ambiguity inherit in @ tokens by marking the current
#       context as a rule and reparsing the spool
function resolve_ruleset_or_nested_statements_ambiguity_as_rule(char) {
    pop_context()  # Remove ruleset_or_nested_statements
    push_context("rule")
    push_context("lspaces")
    indentation += 1
    respawn(tok_chars(spool char))
    spool = ""     # Just reparsed, no need to keep around spool
    pop_context()
}
# resolve_ruleset_or_nested_statements_ambiguity_as_nested_statements
#       Resolves the ambiguity inherit in @ tokens by marking the current
#       context as nested statements
function resolve_ruleset_or_nested_statements_ambiguity_as_nested_statements() {
    # Well this is much more straightforward than ...as_rule
    pop_context()  # Remove ruleset_or_nested_statements
    change_context("nested_statements")  # at -> nested_statements
}
/\/\*/ {
    debug_line($0)

    # /* ... */
    # ^ here
    if (!in_blob_context()) {
        push_context("comment")

        # Mark the start of the comment
        spool_start = length(spool)
        next
    }

    spool = spool $0
    next
}
/\*\// {
    debug_line($0)

    # /* ... */
    #        ^ here
    if (context() == "comment") {
        pop_context()

        # Slice out the comment from the spool since comments can appear
        # anywhere and we want to continue in the previous context
        spool = spool_before(spool_start)
        spool_start = 1
        next
    }

    spool = spool $0
    next
}
/@/ {
    debug_line($0)
    pop_spacing_context_if_found($0)

    # @media { .selector { ...
    # or
    # @namespace ... ;
    # or
    # @page { rule: value; ...
    # ^ here
    if (in_block_context())
        push_context("at")
    # @supports { @media { ... } }
    #             ^ here
    else if (context() == "ruleset_or_nested_statements") {
        resolve_ruleset_or_nested_statements_ambiguity_as_nested_statements()
        push_context("at")
        # ~fallthrough~
    }

    spool = spool $0
    next
}
/\{/ {
    debug_line($0)
    pop_spacing_context_if_found($0)

    # I dont think its legal to just have blank { ... } curly braces, but
    # handle with grace
    if (in_block_context()) {
        push_context("selector")
        # ~fallthrough~
    }
    # @media { .selector { ...
    #                    ^ here
    else if (context() == "ruleset_or_nested_statements") {
        # Resolve ambiguity (see at case below)
        resolve_ruleset_or_nested_statements_ambiguity_as_nested_statements()
        push_context("selector")
        # ~fallthrough~
    }

    # .selector { ...
    #           ^ here (selector)
    # or
    if (context() == "selector") {
        spool_emit_token("SELECTOR")
        indentation += 1

        push_context("rule")
        push_context("lspaces")
        next
    }
    # @media {
    #        ^ here (at)
    # or
    # @page {
    #       ^ here (at)
    else if (context() == "at") {
        spool_emit_token("AT_NESTED")
        indentation += 1
        # with @... {  }
        #           ^ here
        # it is impossible with a single character to figure out whether the
        # next context should be a rule or selector (or at) since at-rules can
        # contain either rules or nested selectors e.g. @media contains
        # selectors, @page contains rules
        #
        # This manifests itself when we encounter a ":" character following a
        # "{" character. If we assume the following context is a rule, then we
        # mischaracterize "foo :bar {" because there are nested statements. If
        # we assume the following context is a selector then we
        # mischaracterize simple rule/values "foo: bar;". The hack is to defer
        # the tokenization of rules and their values until we encounter a ";".
        change_context("nested_statements")
        push_context("ruleset_or_nested_statements")
        push_context("lspaces")
        next
    }

    spool = spool $0
    next
}
/\}/ {
    debug_line($0)
    pop_spacing_context_if_found($0)

    # @page { margin: left }
    #                      ^ here
    if (context() == "ruleset_or_nested_statements") {
        # Read "at" condition in { match first.
        #
        # If we reach } in a ruleset_or_nested_statements context that means that we
        # did not encounter a selector {, so we assume that either the
        # values inside {} are empty, or there was a single rule without a ;
        # terminator (since that is _technically_ valid). So reparse that
        # spool and resolve the ambiguity as we do when we encounter ; in a
        # ruleset_or_nested_statements context
        resolve_ruleset_or_nested_statements_ambiguity_as_rule($0)
        indentation -= 1
        pop_context()  # Remove rule to get to at context
        # ~fallthrough~
    }

    # .selector { rule: value; ... } ...
    #                              ^ here
    # or
    # @page { rule: value; ... }
    #                          ^ here
    if (context() == "rule" || context() == "value") {
        # .selector{rule: value} is valid without a trailing semilicolon,
        # handle that here
        if (context() == "value") {
            spool_emit_token("VALUE")
            indentation -= 1
            pop_context()  # Remove value context, leaving rule context on top
        }

        pop_context()  # Remove the rule context
        # ~fallthrough~
    }

    # .selector {}
    #            ^ here
    # or
    # @media { ... }
    #              ^ here
    # or
    # @page { rule: value; ... }
    #                        ^ here
    if (context() == "selector" || context() == "nested_statements") {
        indentation -= 1
        pop_context()  # Remove the selector or nested_statements context
        push_context("lspaces")
        next
    }

    spool = spool $0
    next
}
/:/ {
    debug_line($0)
    pop_spacing_context_if_found($0)

    # :psuedo-class { ...
    # ^ here
    if (context() == "global")
        push_context("selector")
    # rule: value;
    #     ^ here
    else if (context() == "rule") {
        spool_emit_token("RULE")
        indentation += 1
        push_context("value")
        push_context("lspaces")
        next
    }

    spool = spool $0
    next
}
/;/ {
    debug_line($0)
    pop_spacing_context_if_found($0)

    # rule: value; ...
    #            ^ here
    if (context() == "value") {
        spool_emit_token("VALUE")
        indentation -= 1
        pop_context()  # Remove value context, restore rule context
        push_context("lspaces")
        next
    }
    # @page { rule: value; }
    #                    ^ here
    else if (context() == "ruleset_or_nested_statements") {
        # Resolve ambiguity, we now know we are in a rule context (see at case
        # in /\{/). Because we just consumed a bunch of input without parsing
        # it, we need to reparse that data.
        resolve_ruleset_or_nested_statements_ambiguity_as_rule($0)
        indentation -= 1
        next
    }
    # @namespace ... ; ...
    #                ^ here
    else if (context() == "at") {
        spool_emit_token("AT_REGULAR")
        pop_context()   # Remove at context, probably resulting in global
                        # context, but I think its possible to have an
                        # embedded @. e.g. @media { @keyframes { ... } }
        push_context("lspaces")
        next
    }
    # { rule: value;;; }
    #               ^ here
    else if (context() == "rule")
        # Skip trailing ';'
        next

    spool = spool $0
    next
}
/,/ {
    debug_line($0)
    pop_spacing_context_if_found($0)

    # rule: value1, value2 ...
    #             ^ here
    # or
    # @document url(...), url-prefix(...), ...
    if (context() == "value") {
        spool_emit_token("VALUE")
        push_context("lspaces")
        next
    }
    # .foo, .bar {
    #     ^ here
    # or
    # rgba(0, 0, 0, 0)
    #       ^ here
    if (context() == "selector" || context() == "paren")
        push_context("lspaces")
        # ~fallthrough~

    spool = spool $0
    next
}
/\(|\)/ {
    debug_line($0)
    pop_spacing_context_if_found($0)

    # @media (rule: value) { ...
    #        ^ here      ^ or here
    # rule: function(value1, value2, value3)
    #               ^ or here              ^ or here
    if (context() == "paren" && $0 == ")") {
        pop_context()
        push_context("lspaces")
    }
    else if (!in_blob_context() && $0 == "(") {
        push_context("paren")
        push_context("lspaces")
    }

    spool = spool $0
    next
}
/"/ {
    debug_line($0)
    pop_spacing_context_if_found($0)

    # rule: value, "value2"
    #                     ^ here
    if (context() == "quote") {
        pop_context()
        push_context("lspaces")
    }

    # rule: "value"
    #       ^ possibly here
    # *technically blob contexts includes quote; but already checked for quote
    # context above, so all good
    else if (!in_blob_context()) {
        push_context("quote")
        push_context("lspaces")
    }

    spool = spool $0
    next
}
/\+|~|>/ {
    debug_line($0)
    old_context = context()
    pop_spacing_context_if_found($0)

    # .selector1 + .selector2 {
    #            ^ here
    # or
    # .selector1 ~ .selector2 {
    #            ^ here
    # or
    # .selector1 > .selector2 {
    #            ^ here
    if (context() == "selector" && old_context == "lspaces") {
        spool = spool_before(length(spool)-1)  # Remove prev leading whitesepace
        push_context("lspaces")
        # ~fallthrough~
    }

    spool = spool $0
    next
}
/^$/ {
    debug_line($0)
    # /*
    #   ^ here
    #  irrelevant
    #  */
    if (in_blob_context())
        spool = spool "\n"

    # .selector1
    #           ^ here
    # .selector2 { ...
    # or alternatively, selector may be a @media part
    else if (context() == "selector" || context() == "at" || context() == "ruleset_or_nested_statements") {
        # lets make it .selector1 .subselector2
        spool = spool " "
        push_context("lspaces")
    }

    next
}
/ |\t/ {
    debug_line($0)
    # For leading whitespace lets ignore it
    if (in_block_context() || context() == "lspaces")
        next
    if (context() == "selector" || context() == "at" || context() == "value")
        push_context("lspaces")
        # ~fallthrough~

    spool = spool $0
    next
}
{
    debug_line($0)
    pop_spacing_context_if_found($0)

    # .selector { ...
    # ^ here
    if (context() == "global")
        push_context("selector")

    # ...rule: value;
    #    ^ here
    # or
    # ...rule: value1, value2;
    #          ^ here
    # or basically after any whitespace parts, but the character is not
    # signficant
    spool = spool $0
}
END {
    debug_line($0)
    pop_spacing_context_if_found($0)

    # Here is where we deal with the fact that we may have collected unparsable
    # garbage, or have to deal with a context that allows for a context to be
    # flushed without a ; at EOF. e.g. @import
    if (spool != "") {
        # @import "blah.css"
        #                   ^ here
        if (context() == "at")
            spool_emit_token("AT_REGULAR")
        else
            spool_emit_token("WTF")
    }
}
