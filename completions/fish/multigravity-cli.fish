# multigravity-cli fish completion
set -l commands new list status whoami clone rename delete template export import doctor stats completion help

complete -c multigravity-cli -f -n "not __fish_seen_subcommand_from $commands" -a "$commands"
complete -c multigravity-cli -f -n "not __fish_seen_subcommand_from $commands" -a "(multigravity-cli list --raw 2>/dev/null)"
complete -c multigravity-cli -f -n "__fish_seen_subcommand_from clone rename delete export whoami" -a "(multigravity-cli list --raw 2>/dev/null)"
complete -c multigravity-cli -f -n "__fish_seen_subcommand_from template" -a "save list delete"
complete -c multigravity-cli -f -n "__fish_seen_subcommand_from new" -l auth-only -d "Share settings & MCP, isolate accounts"
complete -c multigravity-cli -f -n "__fish_seen_subcommand_from new" -l from -d "Create from template" -a "(multigravity-cli template list --raw 2>/dev/null)"
complete -c multigravity-cli -f -n "__fish_seen_subcommand_from new" -l copy-from -d "Copy auth from profile" -a "(multigravity-cli list --raw 2>/dev/null)"
