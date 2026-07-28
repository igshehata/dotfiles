function __wtx_base_refs --description 'Emit base refs for wto and wtc completions'
    printf '%s\t%s\n' '@' 'Current branch'
    printf '%s\t%s\n' '^' 'Default branch'
    printf '%s\t%s\n' '-' 'Previous worktree'

    command git rev-parse --is-inside-work-tree >/dev/null 2>/dev/null; or return 0

    for ref in (command git for-each-ref --format='%(refname:short)' refs/heads 2>/dev/null)
        printf '%s\t%s\n' $ref 'Local branch'
    end

    for ref in (command git for-each-ref --format='%(refname:short)' refs/remotes 2>/dev/null)
        if string match -q '*/HEAD' -- $ref
            continue
        end

        printf '%s\t%s\n' $ref 'Remote ref'
    end
end
