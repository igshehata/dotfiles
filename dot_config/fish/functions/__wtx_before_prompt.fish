function __wtx_before_prompt --description 'Return success before the agent prompt separator'
    set -l tokens (commandline --current-process --tokens-expanded --cut-at-cursor)
    set -e tokens[1]

    not contains -- -- $tokens
end
