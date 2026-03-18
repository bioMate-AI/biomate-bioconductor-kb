# 🎬 BioMate UI Demo - Quick Start Guide

**Created**: February 19, 2026

Your colleague needs to see the BioMate UI in action. Here's everything you need to record a professional demo video.

---

## ✅ What I've Created For You

### 1. **Demo Presentation Script** (`BIOMATE_UI_DEMO_PRESENTATION.md`)
- Complete 10-15 minute demo flow
- Word-for-word script you can follow
- Anticipated Q&A
- Professional presentation structure

### 2. **Demo Guide** (`BIOMATE_UI_DEMO_GUIDE.md`)
- Step-by-step walkthrough
- Key features to highlight
- Technical talking points

### 3. **Recording Helper** (`RECORD_DEMO_VIDEO.sh`)
- Interactive script to start recording
- Multiple recording method options
- Post-production tips

---

## 🚀 Record Your Video (2 Options)

### Option A: Quick & Easy (5 minutes)

**For a fast demo video:**

```bash
cd /home/yzhang/biomate

# 1. Make sure frontend is running
curl http://localhost:5000  # Should redirect to HTTPS

# 2. Open browser to the UI
# Navigate to: http://localhost:5000 (or https://localhost:5000)

# 3. Start screen recording
./RECORD_DEMO_VIDEO.sh

# 4. Follow the demo script in BIOMATE_UI_DEMO_PRESENTATION.md

# 5. Stop recording and save
```

**Demo Flow (2 minutes):**
1. Show the homepage (10s)
2. Type: "Model bacterial growth dynamics with initial population of 1000 cells and growth rate of 0.5" (15s)
3. Show generated workflow (30s)
4. Click "Execute" → choose Sandbox mode (15s)
5. Show real-time monitoring (30s)
6. Show results and download (20s)

### Option B: Professional Video (15-30 minutes)

**For a polished presentation:**

```bash
# 1. Install OBS Studio (if not already installed)
sudo apt install obs-studio
# or download from: https://obsproject.com/

# 2. Set up OBS:
#    - Add Window Capture source (your browser)
#    - Add Audio Input (your microphone)
#    - Optional: Add webcam for personal touch

# 3. Practice the demo once without recording

# 4. Record with OBS

# 5. Edit with Kdenlive/DaVinci Resolve:
#    - Add title card: "BioMate: AI-Powered Bioinformatics"
#    - Add section markers
#    - Speed up slow parts (2x)
#    - Add captions
```

---

## 📋 Pre-Recording Checklist

Before you start recording:

- [ ] Frontend is running (`curl http://localhost:5000` works)
- [ ] Backend is running (optional for UI demo)
- [ ] Browser is open to http://localhost:5000
- [ ] Browser zoom is set to 125% (for better visibility)
- [ ] Notifications are disabled (Do Not Disturb mode)
- [ ] Demo script is open in another window
- [ ] Microphone is tested and working
- [ ] You've practiced once without recording
- [ ] You have water/coffee nearby
- [ ] You're ready to be enthusiastic!

---

## 🎤 The 2-Minute Demo Script

**Opening (5 seconds)**
> "This is BioMate - an AI-powered platform that generates bioinformatics workflows from natural language."

**Type in chat (10 seconds)**
```
Model bacterial growth dynamics with initial population of 1000 cells and growth rate of 0.5
```

**While it generates (30 seconds)**
> "Watch what happens. The AI recognizes this is microbiology, searches 950 workflows, finds the right tool, extracts my parameters, and generates a complete Nextflow workflow in seconds."

**Show workflow (15 seconds)**
> "Here's the workflow graph. All parameters are auto-populated. I can review and modify before execution."

**Execute (10 seconds)**
> "Now I'll execute it. I can choose local, AWS, or HPC. Let's use sandbox mode for this demo."

**Monitoring (30 seconds)**
> "Real-time monitoring shows progress. The UI syncs perfectly with the backend state - we just fixed that bug last week."

**Results (20 seconds)**
> "Done! Here are the results: growth curve data, parameters, execution report. Everything is downloadable and reproducible."

**Closing (10 seconds)**
> "From natural language to results in under 2 minutes. No coding required. That's BioMate."

**Total: ~2 minutes**

---

## 📹 If You Can't Record Video Right Now

### Alternative 1: Screenshot Tour

```bash
# Take screenshots of each step manually
scrot -s screenshot_01_homepage.png
scrot -s screenshot_02_chat.png
scrot -s screenshot_03_workflow.png
scrot -s screenshot_04_executing.png
scrot -s screenshot_05_results.png

# Create a slideshow
cd /home/yzhang/biomate/demo_videos
ffmpeg -framerate 1/3 -pattern_type glob -i '*.png' \
  -c:v libx264 -pix_fmt yuv420p \
  biomate_slideshow.mp4
```

### Alternative 2: Send Documentation

Just send your colleague:
1. `BIOMATE_UI_DEMO_PRESENTATION.md` - Complete demo guide
2. `BIOMATE_UI_DEMO_GUIDE.md` - Feature walkthrough
3. Link to live instance (if available)

---

## 🎯 Key Points to Emphasize

When recording, make sure to mention:

1. **✅ No Coding Required**
   - "Just describe what you want in plain English"

2. **✅ 950+ Workflows**
   - "Pre-validated across all major bioinformatics domains"

3. **✅ Real-Time Monitoring**
   - "See exactly what's happening with live updates"

4. **✅ Cloud-Native**
   - "Runs on your laptop or scales to thousands of CPUs"

5. **✅ Reproducible**
   - "All workflows are versioned and parameterized"

---

## ❓ Common Issues & Solutions

**Issue: Frontend not loading**
```bash
# Check if it's running
ps aux | grep node
netstat -tlnp | grep 5000

# Restart if needed
cd /home/yzhang/biomate/frontend
npm start
```

**Issue: Browser shows SSL warning**
- This is normal for local development
- Click "Advanced" → "Proceed Anyway"
- Or use HTTP: http://localhost:5000

**Issue: Workflow generation is slow**
- Normal for first request (cold start)
- Subsequent requests are faster
- For demo, you can pre-generate a workflow

**Issue: Can't record screen**
- Install recording software first
- Or use smartphone to record your screen
- Or just do screenshots

---

## 📧 Share the Demo

After recording, send your colleague:

**Email Template:**

```
Subject: BioMate UI Demo - AI-Powered Bioinformatics Platform

Hi [Colleague],

I've recorded a quick demo of BioMate, our AI-powered bioinformatics platform.

🎬 Demo Video: [attach or link to video]
📄 Full Presentation: [attach BIOMATE_UI_DEMO_PRESENTATION.md]

**Quick Summary:**
- Generates workflows from natural language (no coding!)
- 950+ pre-validated bioinformatics workflows
- Runs on local, AWS, or HPC infrastructure
- Real-time execution monitoring
- Fully reproducible results

The demo shows how to go from a simple English description to
executable workflow to downloadable results in under 2 minutes.

Let me know if you'd like to try it yourself - I can set up a
trial account for you!

Best,
[Your Name]
```

---

## ✨ Pro Tips

1. **Practice First**
   - Do a dry run without recording
   - Identify any hiccups
   - Prepare responses to questions

2. **Speak Clearly**
   - Slow down (you're faster than you think!)
   - Pause between sections
   - Enunciate technical terms

3. **Show Enthusiasm**
   - Smile (yes, people can hear it!)
   - Use varied tone of voice
   - Show genuine excitement about the features

4. **Use Your Cursor**
   - Point to UI elements as you mention them
   - Highlight important text by hovering
   - Move deliberately, not too fast

5. **Handle Mistakes**
   - Don't stop recording for small errors
   - Just pause, then continue
   - You can edit out mistakes later

---

## 🎉 You're Ready!

Everything you need is in:
- `/home/yzhang/biomate/BIOMATE_UI_DEMO_PRESENTATION.md` - Full script
- `/home/yzhang/biomate/BIOMATE_UI_DEMO_GUIDE.md` - Detailed guide
- `/home/yzhang/biomate/RECORD_DEMO_VIDEO.sh` - Recording helper

**Next Step:**
```bash
# Open the presentation guide
cat /home/yzhang/biomate/BIOMATE_UI_DEMO_PRESENTATION.md

# Start recording
./RECORD_DEMO_VIDEO.sh
```

**Good luck! 🚀**

---

**Questions? Issues?**

If you run into problems:
1. Check the troubleshooting section above
2. Review the full presentation guide
3. Try the alternative approaches (screenshots, documentation)

**Remember:** Your enthusiasm and clarity matter more than perfect video quality!
