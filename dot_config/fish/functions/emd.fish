function emd
    if test -z "$argv[1]"
        echo "Error: No filename provided." >&2
        echo "Usage: <pipeline> | save_to_obsidian <filename_without_extension>" >&2
        return 1
    end

    set file_path "/Users/islam.shehata/Documents/Obsidian Vault/k/$argv[1].md"

    Use awk to find the `markdown block, extract its content,
    and redirect it to the specified file in your Obsidian vault.
    awk '/^`markdown/{flag=1; next} /^
  `/{flag=0} flag' >$file_path

    echo "✔ Content saved to $file_path"
end
