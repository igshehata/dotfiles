function lt --description 'Tree view (level 2) with collapsed dependency dirs'
    set -l dep_dirs node_modules .next dist target .venv __pycache__ vendor .gradle build Pods .dart_tool .turbo .cache .nuxt .output .svelte-kit

    set -l dir .
    set -l pass_args
    for arg in $argv
        if test -d "$arg"
            set dir $arg
        end
        set -a pass_args $arg
    end

    # Find which dep dirs actually exist
    set -l found
    for d in $dep_dirs
        if test -d "$dir/$d"
            set -a found $d
        end
    end

    if test (count $found) -gt 0
        set -l ignore_glob (string join '|' $found)
        eza -T --no-permissions --icons --level=2 --git -I "$ignore_glob" $pass_args
        # Print collapsed dirs as a flat list at tree root level
        for d in $found
            echo "├── $d/"(set_color brblack)" [collapsed]"(set_color normal)
        end
    else
        eza -T --no-permissions --icons --level=2 --git $pass_args
    end
end
