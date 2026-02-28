#!/bin/bash
# Post-compact context reminder hook
# Triggers Claude to summarize what it knows after compacting

cat << 'EOF'
<post-compact-context-reminder>
After compacting, provide a brief summary of:
1. Current task being worked on
2. Key decisions/changes made this session
3. Pending items or blockers
4. Immediate next steps
</post-compact-context-reminder>
EOF
