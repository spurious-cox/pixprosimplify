=============================================================================
 PixProSimplify — Anchor-Point Reduction for Pixelmator Pro Shape Layers
=============================================================================

PixProSimplify is a macOS AppleScript applet that reduces the number of
anchor points in a Pixelmator Pro shape (or text) layer while preserving its
visual appearance. Pixelmator Pro has no native "simplify path" feature and
its AppleScript dictionary exposes shape layers but not their anchor points,
so the applet works by round-tripping the layer through SVG and a custom
Python reduction engine.

Applet:   /Applications/PixProSimplify.app
Engine:   ~/bin/pixpro_simplify_engine.py   (analysis + reduction driver)
Reducer:  ~/bin/pixpro_reduce.py            (the point-reduction algorithm)
Source:   ~/My_Applications/PixProSimplify/PixProSimplify.applescript


-----------------------------------------------------------------------------
 HOW TO USE IT
-----------------------------------------------------------------------------

    1. In Pixelmator Pro, select ONE shape or text layer at the top level
       of the Layers list. More than one selected layer is refused.

    2. Run PixProSimplify (/Applications/PixProSimplify.app). It solos the
       layer, exports it, and counts the anchor points.

    3. Choose a reduction level from the list — Min, Mean or Max, each
       shown with the point count it would produce and the percentage
       saved. Mean is preselected. Click Reduce.

    4. The reduced copy arrives as "<name>-reduced", above the hidden
       original, inside a group carrying the original's name.

If no level beats the original the applet says so and stops. If all three
levels converge on the same result it offers a single Reduce/Cancel
confirmation instead of the list.


-----------------------------------------------------------------------------
 HOW A REDUCTION WORKS (the pipeline)
-----------------------------------------------------------------------------

1. SOLO      The selected top-level layer is isolated: every other visible
             top-level layer is temporarily hidden, because Pixelmator's SVG
             export is always whole-document. Visibility is restored
             immediately after the export, exactly as it was found.

2. EXPORT    The document is exported to SVG. Pixelmator still embeds hidden
             layers in the SVG (tagged visibility="hidden"), so the engine
             strips every hidden element the moment the file is loaded —
             otherwise they would contaminate the point counts and output.

3. ANALYZE   The engine estimates three reduction levels for THIS shape
             (see "Techniques" below) and reports, for Min / Mean / Max:
             the epsilon to use, the resulting point count, and the
             percentage saved.

4. CHOOSE    A popup presents the three levels. Special cases:
             - If no level removes any points, an informational dialog with
               a single Cancel button appears instead.
             - If all three levels converge to the same count (typical for
               font glyphs, which are already hand-optimized), a single
               Reduce/Cancel dialog notes the convergence.

5. REDUCE    The chosen epsilon is applied by the reducer and the result is
             written to a new SVG.

6. REGROUP   The reduced SVG is imported back into the document. The new
             layer is named "<original>-reduced", placed directly above the
             original; the original is hidden, and the pair is grouped under
             the original layer's name. Nothing is destroyed — delete the
             group's reduced layer and unhide the original to undo.

TEXT LAYERS  A text layer cannot be reduced directly. The applet duplicates
             it, converts the duplicate into a shape, and reduces that. The
             temporary shape copy is deleted afterward; the final group
             holds "<name>-reduced" (visible) plus the original, still
             editable, text layer (hidden).


-----------------------------------------------------------------------------
 TECHNIQUES USED FOR THE REDUCTION
-----------------------------------------------------------------------------

RDP ON BEZIER ANCHORS
    The reducer applies the Ramer-Douglas-Peucker algorithm to the shape's
    anchor points (not to a flattened polyline). Anchors whose removal
    changes the outline by less than a tolerance ("epsilon", in shape
    units) are dropped; the surviving anchors keep their ORIGINAL Bezier
    in/out handles, so retained curvature is untouched. Closed loops are
    handled by splitting each loop at its point farthest from the start.
    A larger epsilon removes more points.

PER-SHAPE LEVEL ESTIMATION (the error-elbow method)
    A fixed epsilon cannot suit every shape, so the three offered levels
    are computed per shape:
    - The engine sweeps ten log-spaced epsilon values (expressed as
      fractions of the shape's bounding-box diagonal, making the sweep
      scale-invariant).
    - For each candidate, both the original and the reduced curves are
      flattened to dense sample points, and the maximum deviation of the
      original samples from the reduced curve is measured (a directed,
      Hausdorff-style distance, point-to-segment so it is
      sampling-independent), normalized by the bounding-box diagonal.
    - MIN reduction  = largest epsilon whose error stays near-lossless
                       (<= 0.06% of the diagonal).
    - MAX reduction  = largest epsilon whose error stays at the "elbow"
                       of the count-vs-error curve (<= 0.30% of the
                       diagonal, roughly one screen pixel) — the most
                       aggressive level that is still visually faithful.
    - MEAN reduction = the geometric midpoint of the two epsilons.

HIDDEN-ELEMENT STRIPPING
    Both analysis and reduction operate only on visible SVG elements.
    Elements marked visibility="hidden" or display:none (attribute or
    style), including whole hidden groups, are pruned at load time.

KNOWN CHARACTERISTICS
    - Dense auto-traced art reduces dramatically (a 1,692-point traced
      signature reduced to ~440 points with no visible change).
    - Professionally designed font outlines barely reduce (~1-2%): every
      anchor a type designer placed is doing real work. The convergence
      dialog exists for exactly this case.
    - Below roughly 25-30% of the original count, RDP-with-kept-handles
      begins to facet. A future upgrade path is true Bezier curve
      refitting (Schneider's algorithm), which merges runs of curves
      instead of only deleting anchors.


-----------------------------------------------------------------------------
 IF THE RESULT IS NOT WHAT YOU EXPECTED
-----------------------------------------------------------------------------

Multiple layers are created in this process. They are collected into one
group named after the source layer, with the reduced result ("<name>-reduced")
on top.

The BOTTOM layer of that group is your ORIGINAL, untouched and hidden. To
start over: drag it out of the group to the top level of the Layers list and
make it visible, then delete the group and run PixProSimplify again at a
different reduction level.

Nothing is lost by retrying — the original is never modified.


-----------------------------------------------------------------------------
 VERSION HISTORY
-----------------------------------------------------------------------------

v1.0  (2026-07-15)
    Initial release. Whole-document export, error-elbow analysis,
    Min/Mean/Max popup, reduced result added as a new top-level layer
    named "Reduced-<N>pts". Verified end-to-end on a 1,692-point traced
    signature (reduced to 442 points).

v1.1  (2026-07-16)
    Zero-reduction guard: when no level offers fewer points than the
    original (the percentage can even be negative, since closed-loop
    splitting can add a point), an informational dialog with a single
    Cancel button replaces the picker.

v1.2  (2026-07-16)
    Selected-layer soloing. Analysis previously covered every layer in
    the document combined (a 219-point "y" analyzed as 446 because
    leftover layers were counted too). The applet now requires exactly
    one selected top-level layer, hides all others around the export,
    and restores visibility afterward — even if the export fails.

Engine v1.1  (2026-07-16)
    Hidden-element stripping. Pixelmator's SVG export was found to
    include hidden layers (tagged visibility="hidden"); the engine now
    prunes them at load, completing the fix begun in v1.2 and ensuring
    the reduced output contains only the target shape.

v1.3  (2026-07-16)
    Grouped output. The reduced layer is placed directly above the
    original, the original is hidden, and the pair is grouped under the
    original layer's name.

v1.4  (2026-07-16)
    Text-layer support. A selected text layer is duplicated, the copy
    converted into a shape, and the shape reduced. Every cancel/error
    path deletes the temporary copy.

v1.5  (2026-07-16)
    Convergence dialog. When Min, Mean, and Max all yield the same
    count, a single Reduce/Cancel dialog noting the convergence replaces
    the three-way picker (the lowest epsilon is used).

v2.1  (2026-07-16)
    The reduced layer is named "<original>-reduced" (point counts moved
    to the completion notification), and for text sources the temporary
    shape conversion is deleted after reduction: the final group holds
    just the reduced shape (visible) and the original text (hidden).



v2.2  (2026-08-10)
    Targets whichever Pixelmator build is actually in use. Since the Creator
    Studio rebrand there are two installs — com.apple.pixelmator (Creator
    Studio 4.x) and com.pixelmatorteam.pixelmator.x (Pixelmator Pro 3.x) —
    and `tell application "Pixelmator Pro"` bound to a fixed app path at
    compile time. A document open in the other build therefore read as no
    document at all. The build is now resolved at run time by bundle id
    (pixTarget): frontmost first, then any running build with a document.

v2.3  (2026-08-11)
    Self-contained. The reduction engine and its reducer ship inside the
    bundle (Contents/Resources) and are found with `path to resource`, so the
    app no longer needs ~/bin to exist. It falls back to ~/bin if the bundled
    resources are absent.


v2.4.0  (2026-08-15)
    Targets the running Pixelmator by BUNDLE PATH instead of by bundle id.
    Several COPIES of one build can be installed and copies share an
    identifier, so `tell application id` could not tell them apart: it
    addressed whichever copy macOS preferred, launched that copy if it was not
    already running, and then failed on the empty one. The path and pid of
    every running Pixelmator process are read from `ps`, which is the one
    thing that distinguishes identical copies, and everything is keyed to
    that.


v2.4.1  (2026-08-19)
    Signing release; no change to the effect. Signed with the Developer ID
    certificate under the hardened runtime and notarized, plus the two things
    osacompile does not put in an applet:

        com.apple.security.automation.apple-events. The hardened runtime
        stops an app from ASKING for Automation, so without this entitlement
        the applet keeps working on a Mac that already granted access and
        fails on a fresh one with "Not authorized to send Apple events"
        (-1743) — with no way for the user to switch it on by hand, because
        it never appears in the Automation list.

        A real CFBundleIdentifier (com.timmccoy.pixprosimplify). osacompile writes
        none and drops it again on every rebuild, so codesign had been sealing
        the bundle NAME instead: nothing could address the app with
        `tell application id`, and it could hold no defaults domain.


v2.4.2  (2026-09-13)  — current
    Documentation release; no change to the effect. Adds a HOW TO USE IT
    section — numbered steps from selecting the layer, through every dialog
    field and its units, to what the result group contains — and fills in a
    version history that had stopped one release short of the shipping build.
    The copy inside the bundle was refreshed with it, so the Read Me button
    shows the same text.


-----------------------------------------------------------------------------
 Copyright (c) 2026 Timothy McCoy. All rights reserved.

 Developed with the support of Claude (Anthropic) — design, code, and
 testing assistance throughout versions 1.0 through 2.1.
=============================================================================
