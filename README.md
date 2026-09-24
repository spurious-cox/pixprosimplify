# PixProSimplify 2.5.4

Reduces the number of anchor points in a Pixelmator Pro shape while keeping
the shape looking the same. Pixelmator has no simplify-path command and its
AppleScript dictionary does not expose anchor points, so the layer makes a
round trip through SVG and a Python reduction engine.

### [⬇︎ Download the latest release](https://github.com/spurious-cox/pixprosimplify/releases/latest)

Notarized and stapled by Apple — open the DMG and drag PixProSimplify to Applications,
or install it with Homebrew:

```
brew install --cask spurious-cox/tap/pixprosimplify
```
Requires Pixelmator Pro. Both the 3.x build and the Creator Studio build work;
the app binds to whichever one is in front or has a document open.

## Using it

1. Select **one** shape or text layer at the top level of the Layers list.
2. Run PixProSimplify. It solos the layer, exports it, and counts the anchor
   points.
3. Choose a level — **Min**, **Mean** or **Max**, each shown with the point
   count it would produce and the percentage saved — and click **Reduce**.
   Mean is preselected.

If no level beats the original it says so and stops; if all three converge on
the same result it offers one Reduce/Cancel confirmation instead of the list.

## What you get

`<name>-reduced` above the hidden original, both inside a group carrying the
original's name. A text layer is converted to a shape on a temporary copy; the
text layer itself is kept, hidden.

## How it works

Ramer–Douglas–Peucker run over the bezier anchors, with the three levels
estimated per shape by the error-elbow method rather than fixed. The engine and
its reducer ship inside the app bundle, so nothing depends on `~/bin` existing.

## Building

```
osacompile -o /tmp/PixProSimplify.scpt PixProSimplify.applescript
```

Signing uses a Developer ID certificate selected by SHA-1 hash and timestamped,
which is what keeps macOS's Automation grant alive across rebuilds.
`~/My_Applications/_signing/pixpro_release.sh all <App>` signs and notarizes;
`pixpro_publish.sh <App>` wraps it in the DMG and updates the cask.

## Problems or suggestions

Open an issue: https://github.com/spurious-cox/pixprosimplify/issues

## License

MIT. See [LICENSE](LICENSE).
