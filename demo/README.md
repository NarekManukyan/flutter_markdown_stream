# Demo assets

The top-level `README.md` shows two GIFs from this folder:

- `demo.gif`: the hero clip at the top of the README.
- `thinking.gif`: the close-up in the "Thinking section" part.

`demo.mp4` is the same clip as `demo.gif`, for sharing. GitHub strips
`<video>` tags from READMEs and pub.dev doesn't render them, so the README
only uses GIFs.

The README loads them from `raw.githubusercontent.com/.../main/demo/`, so
they only show up after they are merged to `main`. The folder is listed in
`.pubignore` and isn't part of the published package.

All three come from the example app's "Chat features" screen, recorded on
the iOS Simulator.

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
