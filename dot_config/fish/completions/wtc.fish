complete -e -c wtc

complete -c wtc -f -n '__fish_is_nth_token 2' -a '@' -d 'Current branch'
complete -c wtc -f -n '__fish_is_nth_token 2' -a '^' -d 'Default branch'
complete -c wtc -f -n '__fish_is_nth_token 2' -a '-' -d 'Previous worktree'
complete -c wtc -f -n '__wtx_before_prompt' -s b -l base -r -a '(__wtx_base_refs)' -d 'Base ref for the new branch'
complete -c wtc -f -n '__wtx_before_prompt' -a '--base=@' -d 'Use current branch as base'
complete -c wtc -f -n '__wtx_before_prompt' -a '--' -d 'Start Claude prompt'
complete -c wtc -f -n '__wtx_before_prompt' -l clobber -d 'Remove a stale target path first'
complete -c wtc -f -n '__wtx_before_prompt' -l no-verify -d 'Skip worktrunk hooks'
complete -c wtc -f -n '__wtx_before_prompt' -s y -l yes -d 'Skip approval prompts'
complete -c wtc -f -n '__wtx_before_prompt' -s v -l verbose -d 'Increase worktrunk verbosity'
