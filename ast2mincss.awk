#!/usr/bin/env gawk -f
BEGIN {
    stack_top = 0
    context_stack[stack_top] = "global"
    csv_context_stack[stack_top] = ""
    end_context_stack[stack_top] = ""
}
# context The top of the context stack (the current context)
function context() {
    return context_stack[stack_top]
}
# push_context Adds a new context to the stack
function push_context(new_context, end, csv) {
    stack_top += 1
    context_stack[stack_top] = new_context
    csv_context_stack[stack_top] = csv
    end_context_stack[stack_top] = end
}
# pop_context Pops the top context from the stack
function pop_context() {
    end = context_end()
    delete context_stack[stack_top]
    delete csv_context_stack[stack_top]
    delete end_context_stack[stack_top]
    stack_top -= 1
    return end
}
function context_end() {
    return end_context_stack[stack_top]
}
function context_csv() {
    return csv_context_stack[stack_top]
}
function indentation(in_string) {
    delete array
    match($0, /^(\t*).*/, array)
    return length(array[1])
}
function pop_prev_indented_contexts(line, new_context) {
    if (line == "")
        indent = 0
    else
        indent = indentation(line)

    # For nested blocks, we may be dropping more than 1 indent:
    # e.g. @media { @keyframes { to { ... } from { ... } } } * { ... }
    # would drop by 3 indents from the RULE inside "from" when we reach "*"
    for (i = stack_top - 1; i >= indent; i--) {
        if (i == indent && context() == new_context && context_csv() != "")
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
function strip(string) {
    s = string
    gsub(/^ *| *$/, "", s);
    return s
}
function remove_token(line) {
    rest_index = index(line, " ")
    return substr(line, rest_index+1)
}
/^\t*AT.*/ {
    new_context = "at"
    pop_prev_indented_contexts($0, new_context)
    content = remove_token($0)

    if ($1 == "AT_NESTED") {
        printf "%s{", strip(content)
        push_context(new_context, "}")
    } else {
        printf "%s", strip(content)
        push_context(new_context, ";")
    }
    next
}
/^\t*SELECTOR.*/ {
    new_context = "selector"
    pop_prev_indented_contexts($0, new_context)
    content = remove_token($0)

    printf "%s{", strip(content)
    push_context(new_context, "}")
    next
}
/^\t*RULE.*/ {
    new_context = "rule"
    pop_prev_indented_contexts($0, new_context)
    content = remove_token($0)

    if (context() != new_context)
        push_context(new_context, "", ";")
    else
        printf "%s", context_csv()

    printf "%s:", strip(content)
    next
}
/^\t*VALUE.*/ {
    new_context = "value"
    pop_prev_indented_contexts($0, new_context)
    content = remove_token($0)

    if (context() != new_context)
        push_context(new_context, "", ",")
    else
        printf "%s", context_csv()

    printf "%s", strip(content)
    next
}
/^\t*COMMENT.*/ {
    next
}
/^\t*WTF.*/ {
    # This is bad, but we know it is bad so deal with it
    printf "%s", remove_token($0)
}
{
    printf "Encountered unknown node: %s\n", $0
    exit(1)
}
END {
    pop_prev_indented_contexts()
}
