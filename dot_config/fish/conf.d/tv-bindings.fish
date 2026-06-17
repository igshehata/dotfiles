# tv (television) channel keybindings.
# Each binding opens a tv channel; the selected entry is inserted at the cursor.
# Loads after fzf.fish alphabetically, so these override matching fzf.fish chords.

if not status is-interactive && test "$CI" != true
    exit
end

if not type -q tv
    exit
end

function tv_git_log --description 'Pick a commit via tv git-log channel'
    set -l result (tv git-log)
    if test -n "$result"
        commandline -i -- $result
    end
    commandline -f repaint
end

for mode in default insert
    bind --mode $mode ctrl-alt-l tv_git_log
end
