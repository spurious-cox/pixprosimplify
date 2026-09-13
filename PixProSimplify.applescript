-- PixProSimplify v2.4.2
-- v2.3 (2026-08-11): SELF-CONTAINED. The reduction engine and its reducer
--   now ship inside the bundle (Contents/Resources) and are found with
--   `path to resource`, so the app no longer needs ~/bin to exist. Falls
--   back to ~/bin if the resources are absent.
-- v2.2 (2026-08-10): targets whichever Pixelmator build is in use, resolved
--   at run time by bundle id (see pixTarget) instead of a hardcoded one.
-- Reduce the anchor points of the SELECTED top-level shape layer in the
-- front Pixelmator Pro document to a chosen fidelity level (Min / Mean /
-- Max), auto-estimated per shape via the error-elbow method. The reduced
-- shape is added as a new layer named with its point count; the original is
-- left untouched.
-- Pipeline: solo layer -> export SVG -> bundled pixpro_simplify_engine.py ->
--   re-duplicate layer -> restore visibility -> group with original.
-- v2.1 (2026-07-16): the reduced layer is named "<original>-reduced" (point
--   count moved out of the layer name, still shown in the notification), and
--   for text sources the intermediate text-to-shape copy is DELETED after
--   the reduction instead of kept in the group — it is easily recreated
--   from the original text layer, which IS kept (hidden) in the group.
-- v1.5 (2026-07-16): when Min/Mean/Max all converge to the SAME point count
--   (typical for already-optimal outlines like font glyphs), the 3-way
--   picker is replaced by a single Reduce/Cancel dialog noting the
--   convergence. The lowest epsilon is used (equal counts, highest fidelity).
-- v1.4 (2026-07-16): TEXT layers supported — the text layer is duplicated,
--   the copy converted into a shape (in place; `convert into shape` renames
--   the layer to its text content, so it is renamed back explicitly), the
--   shape is what gets simplified, and the final group holds the reduced
--   layer (visible) + the shape copy and the ORIGINAL TEXT layer (hidden).
--   Every early exit (cancel, zero reduction, export error) deletes the
--   shape copy so no stray layer is left behind.
-- v1.3 (2026-07-16): the reduced layer is placed directly ABOVE the original,
--   the original is hidden, and the pair is grouped under the original's
--   name. GOTCHAS (verified in Pixelmator Pro 3.8): `make group from` only
--   works on ADJACENT top-level layers (returns missing value otherwise, no
--   error), and only with refs built inside a `tell document N` block —
--   `layer i of docVar` refs also return missing value. `move layer A to
--   before layer B` places A directly above B.
-- v1.2 (2026-07-16): operate on the SELECTED top-level layer only. SVG
--   export is whole-document, so other layers (incl. leftover Reduced-*pts
--   copies) inflated the counts and got merged into the output; now every
--   other top-level layer is hidden around the export and restored after.
-- v1.1 (2026-07-16): when every level analyzes to 0% reduction, show an
--   informational dialog with a single Cancel button instead of the picker.
-- Created by Claude (Anthropic) for Tim McCoy — 2026-07-15.

-- pixBundle removed 2026-08-10: the target is now resolved at run time by
-- pixTarget() below. It was never referenced -- every tell carried the
-- literal bundle id inline.

-- ============================================================
-- WHICH PIXELMATOR?  (added 2026-08-10)
-- Since the Creator Studio rebrand there are two installs:
--   com.apple.pixelmator             Pixelmator Pro Creator Studio (4.x)
--   com.pixelmatorteam.pixelmator.x  Pixelmator Pro (3.x)
-- `tell application "Pixelmator Pro"` binds to a fixed path at COMPILE time,
-- so a document open in the other build looks like no document at all.
-- pixTarget() picks at run time: frontmost build first, then any running
-- build that has a document open.
-- ============================================================
property kPixIDs : {"com.apple.pixelmator", "com.pixelmatorteam.pixelmator.x"}
property pixApp : ""

on pixTarget()
	set rawPaths to {}
	try
		set psOut to do shell script "/bin/ps -Axo args= | /usr/bin/grep '/Contents/MacOS/Pixelmator' | /usr/bin/grep -v grep | /usr/bin/sed 's|/Contents/MacOS/.*||' | /usr/bin/sort -u"
		-- `do shell script` separates lines with RETURN, not linefeed. Split on
		-- the wrong one and every path arrives glued into a single string.
		set AppleScript's text item delimiters to return
		set rawPaths to text items of psOut
		set AppleScript's text item delimiters to ""
	end try

	-- Keep only genuine Pixelmator Pro builds, identified by the bundle id in
	-- each app's OWN Info.plist. Nothing here depends on what the app is
	-- called or where it lives, so this works on any Mac: renamed bundles,
	-- App Store or Setapp copies, apps in ~/Applications, all fine. It also
	-- excludes the classic Pixelmator (com.pixelmatorteam.pixelmator), whose
	-- dictionary is different and which would fail halfway through.
	set candidates to {}
	repeat with rp in rawPaths
		set p to rp as text
		if p is not "" then
			try
				set theID to do shell script "/usr/bin/defaults read " & quoted form of (p & "/Contents/Info") & " CFBundleIdentifier"
				if theID is in kPixIDs then set end of candidates to p
			end try
		end if
	end repeat
	if candidates is {} then return ""

	-- Which of them, if any, is frontmost. The frontmost process's pid maps
	-- back to its bundle path through ps.
	set frontPath to ""
	try
		tell application "System Events"
			set fpid to unix id of (first application process whose frontmost is true)
		end tell
		set frontPath to do shell script "/bin/ps -p " & fpid & " -o args= | /usr/bin/sed 's|/Contents/MacOS/.*||'"
	end try

	set ordered to {}
	repeat with c in candidates
		set cc to c as text
		if cc is equal to frontPath then set end of ordered to cc
	end repeat
	repeat with c in candidates
		set cc to c as text
		if cc is not equal to frontPath then set end of ordered to cc
	end repeat

	repeat with c in ordered
		set cc to c as text
		try
			using terms from application "Pixelmator Pro"
				tell application cc
					if (count of documents) > 0 then return cc
				end tell
			end using terms from
		end try
	end repeat
	return item 1 of ordered
end pixTarget


on run
	-- Which Pixelmator build to drive; resolved once, used by every tell below.
	set pixApp to pixTarget()
	if pixApp is "" then
		tell me to activate
		display dialog "Pixelmator Pro is not running. Open Pixelmator Pro and a document, select a layer, and try again." buttons {"OK"} default button "OK" with title "PixProSimplify"
		error number -128
	end if

	-- Engine from INSIDE the bundle, so the app is self-contained and works
	-- on a Mac that has no ~/bin. Both pixpro_simplify_engine.py and the
	-- pixpro_reduce.py it imports ship in Contents/Resources; running a
	-- script by path puts its own directory on sys.path, so the import
	-- resolves without any PYTHONPATH juggling.
	-- Falls back to ~/bin if the resource is missing, which keeps an older
	-- bundle working rather than failing outright.
	set engine to ""
	try
		set engine to POSIX path of (path to resource "pixpro_simplify_engine.py")
	end try
	if engine is "" then
		set engine to (POSIX path of (path to home folder)) & "bin/pixpro_simplify_engine.py"
	end if
	set tmpDir to "/tmp/pixprosimplify"
	do shell script "mkdir -p " & quoted form of tmpDir
	set srcSVG to tmpDir & "/source.svg"
	set outSVG to tmpDir & "/reduced.svg"
	set srcRef to POSIX file srcSVG
	set outRef to POSIX file outSVG
	
	-- 1. solo the selected top-level layer, export to SVG, restore visibility
	using terms from application "Pixelmator Pro"
	tell application pixApp
		if (count of documents) is 0 then
			display dialog "PixProSimplify: open a document with a shape first." buttons {"OK"} default button 1 with icon caution
			return
		end if
		set targetName to name of front document
		set layerCount to count of layers of front document

		-- find the single selected top-level layer (a lone layer needs no selection)
		set selIdx to 0
		set selCount to 0
		repeat with i from 1 to layerCount
			if selected of layer i of front document then
				set selCount to selCount + 1
				set selIdx to i
			end if
		end repeat
		if layerCount is 1 then
			set selIdx to 1
			set selCount to 1
		end if
		if selCount is 0 then
			display dialog "No top-level layer is selected." & return & return & "PixProSimplify works on ONE layer at the TOP LEVEL of the Layers list. Select the shape layer to reduce, then run again. (If it is inside a group, drag it out to the top level first.)" buttons {"OK"} default button 1 with icon caution
			return
		end if
		if selCount > 1 then
			display dialog "More than one layer is selected." & return & return & "PixProSimplify reduces ONE shape layer at a time. Select just the layer to reduce, then run again." buttons {"OK"} default button 1 with icon caution
			return
		end if
		set srcLayerName to name of layer selIdx of front document

		-- a TEXT layer can't be reduced directly: duplicate it (copy lands
		-- directly below, at selIdx + 1), convert the copy into a shape (in
		-- place; the convert renames the layer to its text content, so give
		-- it a clean name), and simplify THAT. Class compare must use the
		-- constant, never a string.
		set isText to ((class of layer selIdx of front document) is text layer)
		set workIdx to selIdx
		if isText then
			tell front document
				duplicate layer selIdx
				tell layer (selIdx + 1) to convert into shape
				set name of layer (selIdx + 1) to (srcLayerName & " shape")
			end tell
			set workIdx to selIdx + 1
			set layerCount to count of layers of front document
		end if

		-- SVG export is whole-document: hide every OTHER visible top-level
		-- layer so only the working layer is exported, remembering which to
		-- restore
		set hiddenIdx to {}
		repeat with i from 1 to layerCount
			if i is not workIdx and visible of layer i of front document then
				set visible of layer i of front document to false
				set end of hiddenIdx to i
			end if
		end repeat
		set wasHidden to not (visible of layer workIdx of front document)
		if wasHidden then set visible of layer workIdx of front document to true

		set exportErr to ""
		try
			with timeout of 120 seconds
				export front document to file srcRef as SVG
			end timeout
		on error errMsg
			set exportErr to errMsg
		end try

		-- restore visibility exactly as found, even if the export failed
		repeat with j from 1 to count of hiddenIdx
			set visible of layer (item j of hiddenIdx) of front document to true
		end repeat
		if wasHidden then set visible of layer workIdx of front document to false

		if exportErr is not "" then
			if isText then tell front document to delete layer workIdx
			display dialog "PixProSimplify: SVG export failed." & return & return & exportErr buttons {"OK"} default button 1 with icon caution
			return
		end if
	end tell
	end using terms from
	
	-- 2. analyze -> per-shape Min/Mean/Max estimates
	set analysis to do shell script "/usr/bin/python3 " & quoted form of engine & " analyze " & quoted form of srcSVG
	set optionLines to paragraphs of analysis
	
	set oldTID to AppleScript's text item delimiters
	set AppleScript's text item delimiters to "|"
	set menuChoices to {}
	set epsList to {}
	set cntList to {}
	set pctList to {}
	set origCount to ""
	set anyReduction to false
	repeat with ln in optionLines
		set parts to text items of (ln as text)
		if (count of parts) is 4 then
			set theLabel to item 1 of parts
			set theEps to item 2 of parts
			set theCount to item 3 of parts
			set thePct to item 4 of parts
			if theLabel is "Original" then
				set origCount to theCount
			else
				set end of menuChoices to (theLabel & " — " & theCount & " points (" & thePct & "% fewer)")
				set end of epsList to theEps
				set end of cntList to theCount
				set end of pctList to thePct
				-- pct can be 0 or even negative (closed-loop split adds a point);
				-- only a positive pct is a real reduction
				if (thePct as number) > 0 then set anyReduction to true
			end if
		end if
	end repeat
	set AppleScript's text item delimiters to oldTID

	if (count of menuChoices) is 0 then
		if isText then
			using terms from application "Pixelmator Pro"
				tell application pixApp to tell front document to delete layer workIdx
			end using terms from
		end if
		display dialog "PixProSimplify: no reducible shape paths found in the front document." buttons {"OK"} default button 1 with icon caution
		return
	end if

	-- every level came back 0% — the shape can't be reduced; nothing to choose
	if not anyReduction then
		if isText then
			using terms from application "Pixelmator Pro"
				tell application pixApp to tell front document to delete layer workIdx
			end using terms from
		end if
		activate me
		try
			display dialog "Layer \"" & srcLayerName & "\" is already at its minimum: " & origCount & " anchor points." & return & return & "No level (Min / Mean / Max) offers fewer points than the original." buttons {"Cancel"} default button 1 cancel button 1 with title "PixProSimplify" with icon note
		end try
		return
	end if
	
	-- 3. popup — the 3-way picker, or a single Reduce/Cancel dialog when all
	-- levels converged to the same count (typical for already-optimal
	-- outlines such as font glyphs)
	set converged to false
	if (count of cntList) is 3 then
		if ((item 1 of cntList) is (item 2 of cntList)) and ((item 2 of cntList) is (item 3 of cntList)) then set converged to true
	end if
	activate me
	if converged then
		-- equal counts at every level: use the lowest epsilon (highest fidelity)
		set chosenEps to item 1 of epsList
		set chosenCount to item 1 of cntList
		try
			display dialog "Layer \"" & srcLayerName & "\": " & origCount & " anchor points." & return & return & "All three levels (Min / Mean / Max) converged to the same result: " & chosenCount & " points (" & (item 1 of pctList) & "% fewer)." buttons {"Cancel", "Reduce"} default button "Reduce" cancel button "Cancel" with title "PixProSimplify" with icon note
		on error number -128
			if isText then
			using terms from application "Pixelmator Pro"
				tell application pixApp to tell front document to delete layer workIdx
			end using terms from
		end if
			return
		end try
	else
		set chosen to choose from list menuChoices with title "PixProSimplify" with prompt ("Layer \"" & srcLayerName & "\": " & origCount & " anchor points." & return & "Choose a reduction level (added as a new layer):") default items {item 2 of menuChoices} OK button name "Reduce" cancel button name "Cancel"
		if chosen is false then
			if isText then
			using terms from application "Pixelmator Pro"
				tell application pixApp to tell front document to delete layer workIdx
			end using terms from
		end if
			return
		end if
		set chosenText to item 1 of chosen

		-- find the matching eps + count
		set chosenEps to ""
		set chosenCount to ""
		repeat with i from 1 to count of menuChoices
			if (item i of menuChoices) is chosenText then
				set chosenEps to item i of epsList
				set chosenCount to item i of cntList
			end if
		end repeat
	end if
	
	-- 4. reduce
	do shell script "/usr/bin/python3 " & quoted form of engine & " reduce " & quoted form of srcSVG & " " & quoted form of outSVG & " " & chosenEps
	
	-- 5. reimport: open reduced svg (becomes document 1); target is document 2.
	-- Place the copy directly above the original, hide the original, and group
	-- the pair under the original layer's name. For a text source the temp
	-- shape copy is deleted (recreatable from the retained text layer).
	-- make group only works on ADJACENT layers with refs built inside a
	-- tell-document block.
	using terms from application "Pixelmator Pro"
	tell application pixApp
		with timeout of 120 seconds
			open outRef
		end timeout
		delay 1.5
		set newLayerName to srcLayerName & "-reduced"
		duplicate layer 1 of document 1 to end of layers of document 2
		delay 0.4
		tell document 2
			set name of (last layer) to newLayerName
			move (last layer) to before layer selIdx
			-- the copy now sits at selIdx; the original(s) shifted down one
			if isText then delete layer (selIdx + 2) -- discard the temp shape copy
			set visible of layer (selIdx + 1) to false
			set theGroup to make group from {layer selIdx, layer (selIdx + 1)}
			set name of theGroup to srcLayerName
		end tell
		close document 1 saving no
	end tell
	end using terms from

	display notification ("Added '" & newLayerName & "' (" & chosenCount & " pts, was " & origCount & ") to group '" & srcLayerName & "'; original hidden") with title "PixProSimplify"
end run

