# Demo assets

The top-level `README.md` references two files in this folder:

- `demo.mp4` — plays inline on GitHub.
- `demo.gif` — fallback for pub.dev (pub.dev doesn't render `<video>` tags,
  but it does render `<img>` GIFs).

Both are expected to live at the repo root-relative path `demo/` so that
the `raw.githubusercontent.com` URLs in the README resolve.

## Recording the demo

### 1. Run the example app

```bash
cd example
flutter run -d macos   # or -d chrome / -d ios / the device you prefer
```

Open the **Stream demo** tab and press the **Stream** button once the app
is idle. Pick whichever cursor style you want on the recording.

### 2. Capture the screen

**macOS** — built-in screen recorder (⌘⇧5), record the window only:

```bash
# Or from the command line:
# (space-bar in the ⌘⇧5 overlay also works)
```

**Any platform** — [Kap](https://getkap.co/), [ScreenStudio](https://screen.studio/),
or OBS will all work. Aim for:

- 1280×720 or smaller (smaller = smaller file).
- 10–15 seconds. Enough to see the code block appear.
- 30 fps is plenty; 60 fps just bloats the file.

### 3. Convert / compress with `ffmpeg`

Reasonable MP4 (H.264, web-friendly, ~500 KB–2 MB):

```bash
ffmpeg -i raw.mov \
  -vf "scale=640:-2" \
  -c:v libx264 -preset slow -crf 28 \
  -pix_fmt yuv420p -movflags +faststart \
  -an \
  demo.mp4
```

Matching GIF (pub.dev fallback):

```bash
# Two-pass palette generation yields much smaller, cleaner GIFs than -f gif alone.
ffmpeg -i demo.mp4 -vf "fps=15,scale=640:-1,palettegen" -y palette.png
ffmpeg -i demo.mp4 -i palette.png -lavfi "fps=15,scale=640:-1 [x]; [x][1:v] paletteuse" -y demo.gif
rm palette.png
```

Target: the GIF should be under 5 MB — pub.dev will load it, and GitHub
will inline it nicely. If it's bigger, drop the fps to 10 or the width
to 480.

### 4. Update the README URLs

The README references `your-org` as a placeholder. Before publishing,
replace `your-org` in `README.md` with the actual GitHub org/user that
hosts this repo so the `raw.githubusercontent.com` URLs resolve on
pub.dev.
