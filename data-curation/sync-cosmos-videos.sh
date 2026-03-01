#!/bin/bash
# Sync new files from remote cosmos outputs every 10 minutes

REMOTE="magenta:/home/user/cosmos-predict2.5/outputs/human_pov_scenarios/"
LOCAL="$HOME/cosmos-generated-videos/"
COMMENTS="$LOCAL/comments.json"

mkdir -p "$LOCAL"

# Add a new mp4 entry to comments.json if it doesn't already exist
add_comment_entry() {
    local video_name="$1"
    # Strip .mp4 extension to get the key
    local key="${video_name%.mp4}"

    # Check if key already exists in comments.json
    if python3 -c "
import json, sys
with open('$COMMENTS') as f:
    data = json.load(f)
sys.exit(0 if '$key' in data else 1)
" 2>/dev/null; then
        return 0
    fi

    # Add new entry
    python3 -c "
import json
with open('$COMMENTS') as f:
    data = json.load(f)
data['$key'] = {'rating': None, 'notes': ''}
with open('$COMMENTS', 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
"
    echo "  Added to comments.json: $key"
}

sync_new_files() {
    echo "=========================================="
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Checking for new files..."

    remote_files=$(ssh magenta "find /home/user/cosmos-predict2.5/outputs/human_pov_scenarios/ -type f" 2>/dev/null)

    if [ $? -ne 0 ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: Could not connect to remote. Will retry next cycle."
        return 1
    fi

    new_count=0
    while IFS= read -r remote_path; do
        [ -z "$remote_path" ] && continue
        rel_path="${remote_path#/home/user/cosmos-predict2.5/outputs/human_pov_scenarios/}"
        local_path="${LOCAL}${rel_path}"

        if [ ! -f "$local_path" ]; then
            echo "  NEW: $rel_path"
            mkdir -p "$(dirname "$local_path")"
            scp "magenta:${remote_path}" "$local_path"
            if [ $? -eq 0 ]; then
                echo "  Downloaded: $rel_path"
                ((new_count++))
                # If it's an mp4, add an entry to comments.json
                if [[ "$rel_path" == *.mp4 ]]; then
                    add_comment_entry "$(basename "$rel_path")"
                fi
            else
                echo "  FAILED: $rel_path"
            fi
        fi
    done <<< "$remote_files"

    if [ "$new_count" -eq 0 ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] No new files found."
    else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Downloaded $new_count new file(s)."
    fi
}

echo "Starting cosmos video sync (every 10 minutes)"
echo "Remote: $REMOTE"
echo "Local:  $LOCAL"
echo "Press Ctrl+C to stop"
echo ""

while true; do
    sync_new_files
    echo ""
    echo "Next check in 10 minutes..."
    sleep 600
done
