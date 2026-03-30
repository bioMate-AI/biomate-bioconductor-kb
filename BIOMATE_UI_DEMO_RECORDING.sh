#!/bin/bash
# BioMate UI Demo Video Recording Script
# Date: February 19, 2026
# Purpose: Automated screen recording for UI demonstration

set -e

# Configuration
DEMO_URL="http://localhost:5000"
OUTPUT_DIR="/home/yzhang/biomate/demo_videos"
OUTPUT_FILE="${OUTPUT_DIR}/biomate_demo_$(date +%Y%m%d_%H%M%S).mp4"
SCREEN_RESOLUTION="1920x1080"
FRAMERATE=30
AUDIO_DEVICE="default"  # Change to your microphone device

# Create output directory
mkdir -p "$OUTPUT_DIR"

echo "=================================================="
echo "BioMate UI Demo Recording Script"
echo "=================================================="
echo ""
echo "Output file: $OUTPUT_FILE"
echo "Demo URL: $DEMO_URL"
echo ""
echo "Recording options:"
echo "  1. Screen + audio (with narration)"
echo "  2. Screen only (no audio)"
echo "  3. Screen + cursor highlighting"
echo "  4. Generate animated GIF demo"
echo "  5. Take screenshots only"
echo ""
read -p "Choose option (1-5): " OPTION

case $OPTION in
  1)
    echo "Recording screen with audio..."
    echo "Press Ctrl+C to stop recording"
    ffmpeg -video_size $SCREEN_RESOLUTION \
           -framerate $FRAMERATE \
           -f x11grab \
           -i :0.0 \
           -f pulse \
           -i $AUDIO_DEVICE \
           -c:v libx264 \
           -preset ultrafast \
           -crf 18 \
           -c:a aac \
           -b:a 192k \
           "$OUTPUT_FILE"
    ;;

  2)
    echo "Recording screen only (no audio)..."
    echo "Press Ctrl+C to stop recording"
    ffmpeg -video_size $SCREEN_RESOLUTION \
           -framerate $FRAMERATE \
           -f x11grab \
           -i :0.0 \
           -c:v libx264 \
           -preset ultrafast \
           -crf 18 \
           "$OUTPUT_FILE"
    ;;

  3)
    echo "Recording with cursor highlighting..."
    echo "Press Ctrl+C to stop recording"
    # Requires key-mon for cursor highlighting
    if ! command -v key-mon &> /dev/null; then
      echo "Installing key-mon for cursor highlighting..."
      sudo apt-get install -y key-mon
    fi

    # Start key-mon in background
    key-mon --scale=2 &
    KEYMON_PID=$!

    ffmpeg -video_size $SCREEN_RESOLUTION \
           -framerate $FRAMERATE \
           -f x11grab \
           -i :0.0 \
           -c:v libx264 \
           -preset ultrafast \
           -crf 18 \
           "$OUTPUT_FILE"

    # Kill key-mon when done
    kill $KEYMON_PID
    ;;

  4)
    echo "Generating animated GIF demo..."
    echo "This will record 30 seconds of screen activity"

    # Record 30 seconds
    TEMP_VIDEO="/tmp/biomate_temp_$(date +%s).mp4"
    timeout 30s ffmpeg -video_size $SCREEN_RESOLUTION \
                       -framerate $FRAMERATE \
                       -f x11grab \
                       -i :0.0 \
                       -t 30 \
                       -c:v libx264 \
                       -preset ultrafast \
                       "$TEMP_VIDEO"

    # Convert to GIF
    GIF_FILE="${OUTPUT_DIR}/biomate_demo_$(date +%Y%m%d_%H%M%S).gif"
    ffmpeg -i "$TEMP_VIDEO" \
           -vf "fps=10,scale=1280:-1:flags=lanczos" \
           -c:v gif \
           "$GIF_FILE"

    rm "$TEMP_VIDEO"
    echo "GIF created: $GIF_FILE"
    ;;

  5)
    echo "Taking screenshots..."
    SCREENSHOT_DIR="${OUTPUT_DIR}/screenshots_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$SCREENSHOT_DIR"

    echo ""
    echo "Screenshot guide:"
    echo "1. Home page"
    echo "2. Chat with workflow generation"
    echo "3. Workflow visualization"
    echo "4. Execution monitoring"
    echo "5. Results and download"
    echo ""

    for i in {1..5}; do
      read -p "Press Enter to take screenshot $i..."
      scrot -u "$SCREENSHOT_DIR/step_${i}.png"
      echo "Screenshot $i saved!"
    done

    echo "All screenshots saved to: $SCREENSHOT_DIR"
    ;;

  *)
    echo "Invalid option"
    exit 1
    ;;
esac

echo ""
echo "=================================================="
echo "Recording complete!"
echo "=================================================="
echo "Output: $OUTPUT_FILE"
echo ""
echo "Next steps:"
echo "1. Review the recording"
echo "2. Edit if needed (use kdenlive, openshot, or ffmpeg)"
echo "3. Add title cards and annotations"
echo "4. Export final version"
echo ""
echo "Recommended edits:"
echo "  - Add intro title (0-5s): 'BioMate: AI-Powered Bioinformatics Platform'"
echo "  - Add section titles for each demo part"
echo "  - Slow down cursor movements (2x slow-mo) for clarity"
echo "  - Add text overlays highlighting key features"
echo "  - Add outro with contact info and next steps"
echo ""
echo "Example ffmpeg commands:"
echo ""
echo "# Add intro title card:"
echo "ffmpeg -i $OUTPUT_FILE -vf \"drawtext=text='BioMate Demo':fontsize=60:fontcolor=white:x=(w-text_w)/2:y=(h-text_h)/2:enable='between(t,0,5)'\" output_with_title.mp4"
echo ""
echo "# Speed up boring parts (2x):"
echo "ffmpeg -i $OUTPUT_FILE -filter:v \"setpts=0.5*PTS\" output_faster.mp4"
echo ""
echo "# Add background music:"
echo "ffmpeg -i $OUTPUT_FILE -i background_music.mp3 -c:v copy -c:a aac -map 0:v:0 -map 1:a:0 output_with_music.mp4"
echo ""

# Offer to open the video
if [ -f "$OUTPUT_FILE" ]; then
  read -p "Play the recording now? (y/n): " PLAY
  if [ "$PLAY" = "y" ]; then
    if command -v vlc &> /dev/null; then
      vlc "$OUTPUT_FILE" &
    elif command -v mpv &> /dev/null; then
      mpv "$OUTPUT_FILE" &
    else
      echo "No video player found. Install VLC or mpv to play the recording."
    fi
  fi
fi

echo ""
echo "Demo recording script completed!"
