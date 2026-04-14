#!/bin/bash
set -e

# --- 1. CONFIGURATION ---
TMP=$(mktemp -d)
INPUT_DIR="./reels"
AUDIO_DIR="./audio"
QUOTES_FILE="./assets/quotes.txt"
FONT="./assets/Inter-Black.ttf"
LOGO_PATH="./assets/spotify.png"
OUTPUT_DIR="./output"

mkdir -p "$OUTPUT_DIR"

# Asset Check
[ ! -f "$LOGO_PATH" ] && echo "❌ Assets missing" && exit 1

# Pick assets
FILES=($(find "$INPUT_DIR" -maxdepth 1 -type f \( -iname "*.mp4" -o -iname "*.mov" \) | shuf -n 10))
AUDIO_FILE=$(find "$AUDIO_DIR" -maxdepth 1 -type f -iname "*.mp3" | shuf -n 1)

# --- 2. MERGE & PROCESS ---
echo "🎬 Step 1: Processing Clips..."
i=1
for f in "${FILES[@]}"; do
    ffmpeg -i "$f" -t 1 -vf "scale=1080:1920:force_original_aspect_ratio=decrease,pad=1080:1920:(ow-iw)/2:(oh-ih)/2:black,fps=30" \
    -c:v libx264 -preset superfast -pix_fmt yuv420p -an "$TMP/clip_$i.mp4" -y -loglevel error
    echo "file '$TMP/clip_$i.mp4'" >> "$TMP/list.txt"
    i=$((i+1))
done

MERGED_RAW="$TMP/merged_raw.mp4"
ffmpeg -f concat -safe 0 -i "$TMP/list.txt" -c copy "$MERGED_RAW" -y -loglevel error
DUR=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$MERGED_RAW")

# --- 3. APPLY VISUALS & QUOTE ---
echo "🎨 Step 2: Applying Visuals..."
TOTAL=$(wc -l < "$QUOTES_FILE" | xargs)
line=$((RANDOM % TOTAL + 1))
raw=$(sed -n "${line}p" "$QUOTES_FILE" | perl -pe 's/[^[:ascii:]]//g; s/[\x00-\x1f\x7f]//g' | xargs)
echo "$raw" | fold -s -w 45 > "$TMP/quote.txt"

VISUAL_MASTER="$TMP/visual_master.mp4"
ffmpeg -i "$MERGED_RAW" -i "$LOGO_PATH" -filter_complex "[1:v]scale=180:-1[logo];[0:v][logo]overlay=x=(W-w)/2:y=H-h-120[v];[v]drawtext=fontfile='${FONT}':textfile='$TMP/quote.txt':fontcolor=white:fontsize=35:box=1:boxcolor=black@0.7:x=(w-text_w)/2:y=(h*0.15)[v_f]" \
    -map "[v_f]" -c:v libx264 -preset veryslow -crf 24 -an "$VISUAL_MASTER" -y -loglevel warning

# --- 4. FINAL EXPORT ---
echo "🎵 Step 3: Finalizing Video..."
safe_name=$(echo "$raw" | tr -cd '[:alnum:] ' | cut -c1-100 | xargs)
url_filename="${safe_name// /_}.mp4"
out_file="$OUTPUT_DIR/$url_filename"

ffmpeg -i "$VISUAL_MASTER" -i "$AUDIO_FILE" -c:v copy -c:a aac -shortest "$out_file" -y -loglevel warning

# --- 5. GITHUB UPLOAD (FORCE PUSH TO SAVE SPACE) ---
if [ -f "$out_file" ]; then
    echo "-----------------------------------------------"
    echo "📤 UPLOADING TO PUBLIC REPO..."

    git config --global user.name "github-actions[bot]"
    git config --global user.email "github-actions[bot]@users.noreply.github.com"

    # Detect branch
    CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
    echo "🌿 Detected branch: $CURRENT_BRANCH"

    # Cleanup old videos in output folder
    find "$OUTPUT_DIR" -type f ! -name "$url_filename" -delete
    
    git add .
    git add "$out_file"

    RAW_URL="https://raw.githubusercontent.com/${GITHUB_REPOSITORY}/${CURRENT_BRANCH}/output/${url_filename}"

    if [ -n "$GITHUB_ACTIONS" ]; then
        echo "⚙️ Force pushing to $CURRENT_BRANCH..."
        git commit -m "Refresh Reel: $safe_name" || git commit --amend --no-edit
        git push origin "$CURRENT_BRANCH" --force
    fi

    # --- 6. WEBHOOK CALL ---
    if [ -n "$WEBHOOK_URL" ]; then
        echo "📡 Sending Webhook..."
        PAYLOAD=$(cat <<EOF
{
  "fileUrl": "$RAW_URL",
  "fileName": "$safe_name"
}
EOF
)
        curl -L -X POST -H "Content-Type: application/json" -d "$PAYLOAD" "$WEBHOOK_URL"
        echo -e "\n✨ Process Complete."
    fi
    echo "-----------------------------------------------"
else
    echo "❌ Error: Final video file was not created."
    exit 1
fi
