function wtx -d "Bootstrap tmux worktree window"
    if test (count $argv) -lt 2
        echo "Usage: wtx <agent> <branch> [wt-switch-args...] [-- prompt...]" >&2
        return 1
    end

    set -l agent $argv[1]
    set -l branch $argv[2]
    set -l wt_args
    set -l prompt
    set -l parsing_prompt 0

    for arg in $argv[3..-1]
        if test $parsing_prompt -eq 1
            set -a prompt $arg
        else if test "$arg" = --
            set parsing_prompt 1
        else
            set -a wt_args $arg
        end
    end

    set -l branch_exists 0
    set -l remote_branch_exists 0

    command git show-ref --verify --quiet "refs/heads/$branch"
    and set branch_exists 1

    if test $branch_exists -eq 0
        command git show-ref --verify --quiet "refs/remotes/$branch"
        and begin
            set branch_exists 1
            set remote_branch_exists 1
        end
    end

    if test $branch_exists -eq 0
        set -l remote_matches (command git for-each-ref --format='%(refname:short)' refs/remotes 2>/dev/null | string match -- "*/$branch")

        if test (count $remote_matches) -gt 0
            set branch_exists 1
            set remote_branch_exists 1
        end
    end

    if test $branch_exists -eq 0
        command git ls-remote --exit-code --heads origin "$branch" >/dev/null 2>/dev/null
        and begin
            command git fetch origin "+refs/heads/$branch:refs/remotes/origin/$branch" >/dev/null 2>/dev/null; or return 1
            set branch_exists 1
            set remote_branch_exists 1
        end
    end

    if test $remote_branch_exists -eq 1
        wt switch "$branch" $wt_args; or return 1
    else if test $branch_exists -eq 1
        wt switch $branch $wt_args; or return 1
    else
        wt switch --create $branch $wt_args; or return 1
    end

    set -l wt_dir (pwd)
    set -l dev_pane (tmux split-window -h -l 20% -d -P -F '#{pane_id}' -t "$TMUX_PANE" -c "$wt_dir"); or return 1
    tmux send-keys -t "$dev_pane" 'mise run all:portless' C-m; or return 1

    if test (count $prompt) -gt 0
        exec $agent $prompt
    else
        exec $agent
    end
end
