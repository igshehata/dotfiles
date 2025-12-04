# ============================================================================
# Television (tv) - Smart Autocomplete Integration
# Ctrl+T: Fuzzy find files, directories, and commands
# Note: Ctrl+R remains with atuin for shell history
# ============================================================================

function __tv_parse_commandline --description 'Parse the current command line token and return split of existing filepath, and query'
    set -l tv_query ''
    set -l prefix ''
    set -l dir '.'

    set -l -- fish_major (string match -r -- '^\d+' $version)
    set -l -- fish_minor (string match -r -- '^\d+\.(\d+)' $version)[2]

    set -l -- match_regex '(?<tv_query>[\s\S]*?(?=\n?$)$)'
    set -l -- prefix_regex '^-[^\s=]+=|^-(?!-)\S'
    if test "$fish_major" -eq 3 -a "$fish_minor" -lt 3
        or string match -q -v -- '* -- *' (string sub -l (commandline -Cp) -- (commandline -p))
        set -- match_regex "(?<prefix>$prefix_regex)?$match_regex"
    end

    if test "$fish_major" -ge 4
        string match -q -r -- $match_regex (commandline --current-token --tokens-expanded | string collect -N)
    else if test "$fish_major" -eq 3 -a "$fish_minor" -ge 2
        string match -q -r -- $match_regex (commandline --current-token --tokenize | string collect -N)
        eval set -- tv_query (string escape -n -- $tv_query | string replace -r -a '^\\\\(?=~)|\\\\(?=\$\w)' '')
    else
        set -l -- cl_token (commandline --current-token --tokenize | string collect -N)
        set -- prefix (string match -r -- $prefix_regex $cl_token)
        set -- tv_query (string replace -- "$prefix" '' $cl_token | string collect -N)
        eval set -- tv_query (string escape -n -- $tv_query | string replace -r -a '^\\\\(?=~)|\\\\(?=\$\w)|\\\\n\\\\n$' '')
    end

    if test -n "$tv_query"
        if test \( "$fish_major" -ge 4 \) -o \( "$fish_major" -eq 3 -a "$fish_minor" -ge 5 \)
            set -- tv_query (path normalize -- $tv_query)
            set -- dir $tv_query
            while not path is -d $dir
                set -- dir (path dirname $dir)
            end
        else
            if test "$fish_major" -eq 3 -a "$fish_minor" -ge 2
                string match -q -r -- '(?<tv_query>^[\s\S]*?(?=\n?$)$)' \
                    (string replace -r -a -- '(?<=/)/|(?<!^)/+(?!\n)$' '' $tv_query | string collect -N)
            else
                set -- tv_query (string replace -r -a -- '(?<=/)/|(?<!^)/+(?!\n)$' '' $tv_query | string collect -N)
                eval set -- tv_query (string escape -n -- $tv_query | string replace -r '\\\n$' '')
            end
            set -- dir $tv_query
            while not test -d "$dir"
                set -- dir (dirname -z -- "$dir" | string split0)
            end
        end

        if not string match -q -- '.' $dir; or string match -q -r -- '^\./|^\.$' $tv_query
            if test "$fish_major" -ge 4
                string match -q -r -- '^'(string escape --style=regex -- $dir)'/(?<tv_query>[\s\S]*)' $tv_query
            else if test "$fish_major" -eq 3 -a "$fish_minor" -ge 2
                string match -q -r -- '^/?(?<tv_query>[\s\S]*?(?=\n?$)$)' \
                    (string replace -- "$dir" '' $tv_query | string collect -N)
            else
                set -- tv_query (string replace -- "$dir" '' $tv_query | string collect -N)
                eval set -- tv_query (string escape -n -- $tv_query | string replace -r -a '^/?|\\\n$' '')
            end
        end
    end

    if test -d "$dir"; and not string match -q '*/$' -- $dir
        set dir "$dir/"
    end

    string escape -n -- "$dir" "$tv_query" "$prefix"
end

function tv_smart_autocomplete
    set -l commandline (__tv_parse_commandline)
    set -lx dir $commandline[1]
    set -l tv_query $commandline[2]
    set -l current_prompt (commandline --current-process)

    printf "\n"

    if set -l result (tv $dir --autocomplete-prompt "$current_prompt" --input $tv_query --inline)
        commandline -t ''

        if test "$dir" = "./"
            set dir ""
        end

        for i in $result
            commandline -t -- (string escape -- "$dir$i")' '
        end
    end

    printf "\033[A"
    commandline -f repaint
end

# Bind Ctrl+T for TV smart autocomplete only
# Ctrl+R remains with atuin for history
for mode in default insert
    bind --mode $mode ctrl-t tv_smart_autocomplete
end
