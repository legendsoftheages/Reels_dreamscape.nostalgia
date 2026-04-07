 TMP=$(mktemp -d)
          INPUT_DIR="./reels"
          AUDIO_DIR="./audio"
          FONT="./Inter-Black.ttf"
          LOGO_PATH="./spotify.png"
          QUOTES_FILE="./quotes.txt"
          OUTPUT_DIR="./output"

          mkdir -p "$OUTPUT_DIR"

          FILES=($(find "$INPUT_DIR" -maxdepth 1 -type f -iname "*.mp4" | shuf | head -n 15))
          [ ${#FILES[@]} -eq 0 ] && echo "❌ No .mp4 files found" && exit 1

          AUDIO_FILE=$(find "$AUDIO_DIR" -maxdepth 1 -type f -iname "*.mp3" | shuf | head -n 1)
          [ -z "$AUDIO_FILE" ] && echo "❌ No audio file found" && exit 1

          [ ! -f "$QUOTES_FILE" ] && echo "❌ quotes.txt not found" && exit 1
          [ ! -f "$LOGO_PATH" ] && echo "❌ spotify.png not found" && exit 1

          TOTAL=$(wc -l < "$QUOTES_FILE")
          [ "$TOTAL" -eq 0 ] && echo "❌ quotes.txt empty" && exit 1

          i=1
          for f in "${FILES[@]}"; do
            echo "➡️ Processing: $f"

            DURATION=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$f")
            START=$(awk -v d="$DURATION" 'BEGIN{srand(); if(d>1) printf "%.3f", rand()*(d-1); else print 0}')

            ffmpeg -ss "$START" -i "$f" -t 1 \
              -vf "scale=1080:1920:force_original_aspect_ratio=decrease,pad=1080:1920:(ow-iw)/2:(oh-ih)/2,fps=30" \
              -c:v libx264 -preset veryfast -crf 23 -pix_fmt yuv420p \
              -an "$TMP/clip_$i.mp4" -y -loglevel error

            [ -f "$TMP/clip_$i.mp4" ] && echo "file '$TMP/clip_$i.mp4'" >> "$TMP/list.txt"
            i=$((i+1))
          done

          [ ! -s "$TMP/list.txt" ] && echo "❌ No clips created" && exit 1

          ffmpeg -f concat -safe 0 -i "$TMP/list.txt" -c copy "$TMP/merged.mp4" -y -loglevel error

          VIDEO_DURATION=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$TMP/merged.mp4")
          FADE_START=$(awk -v d="$VIDEO_DURATION" 'BEGIN{print (d>2)?d-2:0}')

          ffmpeg -i "$TMP/merged.mp4" -i "$AUDIO_FILE" \
            -filter_complex "[1:a]afade=t=out:st=$FADE_START:d=2[a]" \
            -map 0:v -map "[a]" -c:v copy -c:a aac -shortest "$TMP/final.mp4" -y -loglevel error

          line=$((RANDOM % TOTAL + 1))
          TEXT=$(sed -n "${line}p" "$QUOTES_FILE")

          SAFE=$(echo "$TEXT" | tr -cd '[:alnum:] ' | cut -c1-30 | xargs)
          OUT="$OUTPUT_DIR/${SAFE}.mp4"

          ffmpeg -i "$TMP/final.mp4" -i "$LOGO_PATH" \
            -vf "drawtext=fontfile=$FONT:text='$TEXT':fontcolor=white:fontsize=40:x=(w-text_w)/2:y=(h*0.2)" \
            -c:v libx264 -preset veryfast -crf 23 -pix_fmt yuv420p \
            -c:a copy "$OUT" -y

          echo "✅ Done: $OUT"
