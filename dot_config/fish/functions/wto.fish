function wto -d "Create worktree + tmux window with OpenCode and dev server"
    if test (count $argv) -lt 1
        echo "Usage: wto <branch> [wt-switch-args...] [-- prompt...]" >&2
        return 1
    end

    if test -z "$TMUX"
        echo "Not inside tmux." >&2
        return 1
    end

    set -l branch $argv[1]
    set -l wt_args
    set -l prompt
    set -l rest $argv[2..-1]
    set -l has_flag 0
    set -l seen_separator 0

    for arg in $rest
        if test "$arg" = --
            set seen_separator 1
        else if string match -qr '^-' -- $arg
            set has_flag 1
        end
    end

    if test $seen_separator -eq 0 -a $has_flag -eq 0
        set prompt $rest
    else
        set -l parsing_prompt 0

        for arg in $rest
            if test $parsing_prompt -eq 1
                set -a prompt $arg
            else if test "$arg" = --
                set parsing_prompt 1
            else
                set -a wt_args $arg
            end
        end
    end

    set -l win_name (string replace -r '^(feat|fix|chore|refactor|docs|test|perf|ci|build|style)/' '' $branch | string replace -a '/' '-')
    set -l target_dir (pwd)
    set -l bootstrap_args wtx opencode $branch $wt_args -- $prompt
    set -l bootstrap_cmd (string join ' ' -- (string escape -- $bootstrap_args))
    set -l pane_id (tmux new-window -P -F '#{pane_id}' -n "$win_name" -c "$target_dir"); or return 1

    tmux send-keys -l -t "$pane_id" "$bootstrap_cmd"; or return 1
    tmux send-keys -t "$pane_id" C-m; or return 1
end
