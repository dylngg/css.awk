#!/usr/bin/env gawk -f
BEGIN {
    stack_top = 0
    context_stack[stack_top] = "global"
    context_is_multivalued_stack[stack_top] = ""
}
# context The top of the context stack (the current context)
function context() {
    return context_stack[stack_top]
}
# context_is_multivalued Returns "true" or "" (false) if the current context
#                        is mutlivalued
function context_is_multivalued() {
    return context_is_multivalued_stack[stack_top]
}
# push_context Adds a new context to the stack
function push_context(new_context) {
    stack_top += 1
    context_stack[stack_top] = new_context
    delete context_values
}
# push_context Adds a new context to the stack that is expected to contain
#              more than one value
function push_multivalued_context(new_context) {
    push_context(new_context)
    context_is_multivalued_stack[stack_top] = ""
}
# push_singlevalue_context Adds a new context that only contains one value
function push_singlevalue_context(new_context) {
    push_context(new_context)
    context_is_multivalued_stack[stack_top] = "true"
}
# pop_context Pops the top context from the stack
function pop_context() {
    emit_token_values(toupper(context()), stack_top-1)
    delete context_stack[stack_top]
    delete context_is_multivalued_stack[stack_top]
    delete context_values
    stack_top -= 1
}
# emit_token_values Emits the context values with the given token and
#                   indentation amount
function emit_token_values(token, indentation) {
    for (value in context_values) {
        for (i = 0; i < indentation; i++)
            printf "\t"

        print token " " value
    }
}
# indentation Returns the number of tab indents the string given has
function indentation(in_string) {
    delete array
    match($0, /^(\t*).*/, array)
    return length(array[1])
}
# change_to_multivalued_context Switches the current context to the new given
#                               mutlivalued context and pops the previous
#                               contexts if necessary.
function change_to_multivalued_context(line, new_context) {
    pop_indented_contexts(new_context)
    push_multivalued_context(new_context)
}
# change_to_singlevalue_context Switches the current context to the new given
#                               single value context and pops the previous
#                               contexts if necessary.
function change_to_singlevalue_context(line, new_context) {
    pop_indented_contexts(new_context)
    push_singlevalue_context(new_context)
}
# pop_indented_contexts Pops previous contexts based on the indentation change
function pop_indented_contexts(line, new_context) {
    if (line == "")
        indent = 0
    else
        indent = indentation(line)

    # For nested blocks, we may be dropping more than 1 indent:
    # e.g. @media { @keyframes { to { ... } from { ... } } } * { ... }
    # would drop by 3 indents from the RULE inside "from" when we reach "*"
    for (i = stack_top - 1; i >= indent; i--) {
        if (i == indent && context() == new_context && context_is_multivalued())
            # For things like:
            # RULE ...
            #     VALUE ...
            # RULE ...
            #
            # we want to not remove the previous RULE context. If however we
            # get something like:
            # AT ...
            # SELECTOR ...
            #
            # or even
            # AT ...
            # AT ...
            #
            # then we want to pop the AT context
            continue

        printf "%s", pop_context()
    }
}
# add_context_value Stores the given value into the context value buffer
function add_context_value(value) {
    # implicitly dedup here
    context_values[value] = ""
}
# strip Strips trailing and leading whitespace from the string
function strip(string) {
    s = string
    gsub(/^ *| *$/, "", s);
    return s
}
# parse_token_value Returns the token value from the token
function parse_token_value(line) {
    rest_index = index(line, " ")
    return substr(line, rest_index+1)
}
# parse_and_strip_token_value Returns the token value from the token and
#                             strips it
function parse_and_strip_token_value(line) {
    return strip(parse_token_value(line))
}
# value_is_quoted Returns whether the given value has double quotes
function value_is_quoted(value) {
    if (match(value, /^".*"$/) != 0)
        return "true"
    return ""
}
# strip_quotes Removes the expected quoted from the given value
function strip_quotes(value) {
    return substr(substr(value, 2), 0, length(value)-2)
}
# quoted_value_is_identifier Returns whether the value with quotes is a CSS
#                            identifier type
function quoted_value_is_identifier(value) {
    # See https://developer.mozilla.org/en-US/docs/Web/CSS/custom-ident
    # A resonable, yet not nearly complete rule, ignoring unicode, is
    # [a-zA-Z\-_0-9]+, but cannot start with a digit nor a hyphen
    # followed by a digit or hyphen:
    if (match(value, /^"\-?[a-zA-Z_][a-zA-Z\-_0-9]*"$/) != 0)
        return "true"
    return ""
}
/^\t*AT_REGULAR.*/ {
    change_to_singlevalue_context($0, "at_regular")
    print $0
    next
}
/^\t*AT_NESTED.*/ {
    change_to_singlevalue_context($0, "at_nested")
    print $0
    next
}
/^\t*SELECTOR.*/ {
    change_to_singlevalue_context($0, "selector")
    print $0
    next
}
/^\t*RULE.*/ {
    change_to_singlevalue_context($0, "rule")
    print $0
    next
}
/^\t*VALUE.*/ {
    content = parse_and_strip_token_value($0)

    if (context() != "value")
        change_to_multivalued_context($0, "value")

    # Sometimes I find myself quoting font-family values, even if they are
    # not necessary; unquote those even though *technically* those strings
    # are invalid
    if (value_is_quoted(content) && quoted_value_is_identifier(content)) {
        content = strip_quotes(content)
    }

    add_context_value(content)

    next
}
/^\t*COMMENT.*/ {
    print $0
    next
}
/^\t*WTF.*/ {
    print $0
}
{
    printf "Encountered unknown node: %s\n", $0
    exit(1)
}
END {
    pop_indented_contexts()
}
