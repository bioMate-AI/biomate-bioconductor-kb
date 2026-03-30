#!/bin/bash
# Simple screen recording script for BioMate demo

echo "=================================="
echo "BioMate UI Demo Video Recording"
echo "=================================="
echo ""
echo "This script will help you record the BioMate UI demo."
echo ""
echo "Prerequisites:"
echo "1. Install OBS Studio (recommended) or SimpleScreenRecorder"
echo "2. Open http://localhost:5000 in your browser"
echo "3. Prepare the demo script (see BIOMATE_UI_DEMO_PRESENTATION.md)"
echo ""
read -p "Press Enter when ready to continue..."

echo ""
echo "Recording Method Options:"
echo ""
echo "Option 1: OBS Studio (Recommended - Professional Quality)"
echo "  - Best for polished presentations"
echo "  - Supports scene switching, overlays, webcam"
echo "  - Install: sudo apt install obs-studio (or download from obsproject.com)"
echo ""
echo "Option 2: SimpleScreenRecorder (Easy & Fast)"
echo "  - Best for quick demos"
echo "  - Simple interface, good quality"
echo "  - Install: sudo apt install simplescreenrecorder"
echo ""
echo "Option 3: FFmpeg Command Line (Advanced)"
echo "  - Best for automation"
echo "  - Requires X11 display"
echo "  - Command: ffmpeg -video_size 1920x1080 -framerate 30 -f x11grab -i :0.0 output.mp4"
echo ""

read -p "Which method? (1/2/3): " METHOD

case $METHOD in
  1)
    echo ""
    echo "Launching OBS Studio..."
    echo ""
    echo "OBS Quick Setup:"
    echo "1. Add Source → Window Capture → Select your browser"
    echo "2. Add Source → Audio Input Capture → Select your microphone"
    echo "3. Click 'Start Recording'"
    echo "4. Perform your demo"
    echo "5. Click 'Stop Recording'"
    echo "6. Files saved to ~/Videos by default"
    echo ""
    if command -v obs &> /dev/null; then
      obs &
    else
      echo "OBS not installed. Install with:"
      echo "  Ubuntu: sudo apt install obs-studio"
      echo "  macOS: brew install --cask obs"
      echo "  Windows: Download from obsproject.com"
    fi
    ;;

  2)
    echo ""
    echo "Launching SimpleScreenRecorder..."
    echo ""
    echo "SimpleScreenRecorder Setup:"
    echo "1. Select recording area (full screen recommended)"
    echo "2. Enable audio input (your microphone)"
    echo "3. Choose output file location"
    echo "4. Click 'Start Recording'"
    echo "5. Perform your demo"
    echo "6. Click 'Stop Recording'"
    echo ""
    if command -v simplescreenrecorder &> /dev/null; then
      simplescreenrecorder &
    else
      echo "SimpleScreenRecorder not installed. Install with:"
      echo "  sudo apt install simplescreenrecorder"
    fi
    ;;

  3)
    echo ""
    echo "FFmpeg Command Line Recording"
    echo ""
    OUTPUT_FILE="$HOME/Videos/biomate_demo_$(date +%Y%m%d_%H%M%S).mp4"
    mkdir -p "$HOME/Videos"

    echo "Recording will start in 5 seconds..."
    echo "Output file: $OUTPUT_FILE"
    echo "Press Ctrl+C to stop recording"
    echo ""
    sleep 5

    ffmpeg -video_size 1920x1080 \
           -framerate 30 \
           -f x11grab \
           -i :0.0 \
           -f pulse \
           -i default \
           -c:v libx264 \
           -preset ultrafast \
           -crf 18 \
           -c:a aac \
           -b:a 192k \
           "$OUTPUT_FILE"

    echo ""
    echo "Recording saved to: $OUTPUT_FILE"
    ;;

  *)
    echo "Invalid option"
    exit 1
    ;;
esac

echo ""
echo "=================================="
echo "After Recording:"
echo "=================================="
echo ""
echo "1. Review the video"
echo "2. Edit if needed (add intro/outro, trim mistakes)"
echo "3. Add captions/subtitles for accessibility"
echo "4. Export final version"
echo "5. Share with your colleague!"
echo ""
echo "Video Editing Tools:"
echo "  - Kdenlive (Linux, free, powerful)"
echo "  - DaVinci Resolve (All platforms, professional)"
echo "  - OpenShot (All platforms, beginner-friendly)"
echo ""
echo "Done!"
