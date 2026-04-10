#!/bin/bash
set -e

# --- CONFIGURATION ---
# List the folders you want to sync, separated by spaces
SYNC_FOLDERS="audio" 

echo "🔐 Setting up Private Smart Sync..."

# 1. Install Rclone
sudo apt-get install rclone -y --quiet

# 2. Authenticate the Bot
mkdir -p ~/.config/rclone
echo "$GDRIVE_SERVICE_ACCOUNT" > ~/.config/rclone/service_account.json

cat <<EOF > ~/.config/rclone/rclone.conf
[private_drive]
type = drive
service_account_file = ~/.config/rclone/service_account.json
scope = drive.readonly
EOF

# 3. Loop through and Mirror Folders
if [ -n "$GDRIVE_FOLDER_ID" ]; then
    for FOLDER in $SYNC_FOLDERS; do
        echo "🔄 Mirroring (Syncing) Folder: $FOLDER..."
        
        # Ensure the local folder exists
        mkdir -p "./$FOLDER"

        # 'sync' will DELETE files in GitHub that no longer exist in GDrive
        rclone sync "private_drive:$FOLDER" "./$FOLDER" \
            --drive-root-folder-id "$GDRIVE_FOLDER_ID" \
            --checksum \
            --verbose \
            --transfers 4
    done
else
    echo "❌ ERROR: GDRIVE_FOLDER_ID missing" && exit 1
fi

# 4. PUSH TO REPOSITORY
# This step makes the files visible in your GitHub "Code" tab
echo "📤 Committing and Pushing to GitHub..."
rm ~/.config/rclone/service_account.json # Security: remove key before push

git config --global user.name "github-actions[bot]"
git config --global user.email "github-actions[bot]@users.noreply.github.com"

git add .
# [skip ci] prevents the action from triggering itself in an infinite loop
git commit -m "Automated Warehouse Sync [skip ci]" || echo "No changes to commit"
git push origin main

echo "✅ Sync and Push complete. Check your repo now!"
