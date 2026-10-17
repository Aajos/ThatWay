---
id: p5-accessibility
title: Accessibility testing
type: process
tags: [process, testing]
---
# Accessibility testing

A navigation app is used in sun, rain, in motion, one-handed, with a phone held at arm's length: *situational* disability. Doing this properly also serves people with permanent ones, and it is an App Store review expectation. This note says what to test, exactly how, what passes, and **what is known to be wrong today**.

Do this: for every UI change (a 10-minute smoke pass), and in full before each TestFlight build ([[P1 Stages and the MVP line]], S2 to S4).

## Findings as of 2026-10-09 (the honest starting point)
| # | Finding | Evidence | Severity |
|---|---|---|---|
| A1 | **Contrast of text on the accent colour is below the guideline on three of four themes.** White on Ember coral is 3.1:1, white on Paper orange is **2.6:1**, white on Arcade pink is 3.5:1; Tide passes at 8.9:1. Small bold labels (GUIDE, END, CONFIRM, SIGN IN) need 4.5:1 (3:1 only if 18.7 pt bold or 24 pt) | Computed from `AppTheme` hex values with the WCAG formula (script in the appendix) | High for Paper (fails even the 3:1 large-text bar) |
| A2 | **Accent against the Paper background is 2.4:1**, below the 3:1 needed for UI components (the carousel border, the dial ring, icon strokes) | same | Medium |
| A3 | **VoiceOver has almost nothing to say about the compass.** Explicit accessibility modifiers exist only on the carousel (label, value and an adjustable action), the map buttons, the compass-warning overlay, the friends row and the Find sheet. The dial, the guidance cards, the ETA row, the search results and the tab bar rely on SwiftUI defaults | `grep -rn accessibility ThatWay` | High: the app's core output is unreadable by VoiceOver |
| A4 | **Reduce Motion is honoured only by the carousel.** The dial's springs, the card slides, the trip start and end transitions ignore it | `accessibilityReduceMotion` appears in one file | Medium |
| A5 | **Reduce Transparency, Increase Contrast, Differentiate Without Color and Bold Text are not handled anywhere** (the map buttons and cards use translucent materials) | no uses in source | Medium |
| A6 | **Dynamic Type works to the largest accessibility size** for the compass screens, guidance cards, Profile, Store, search, Map and sign-in; the dial and top-bar chrome are deliberately capped so geometry holds | Verified on the simulator at `accessibility-extra-extra-extra-large`, 2026-10-09 | Passing |
| A7 | "Voice of directions" and "Haptics on turns" settings are stored but read by nothing, so a user who cannot look at the screen has no non-visual turn cue to switch on | [[03 Known gaps]], [[haptics-ios]], [[audio-manager]] | High for blind and low-vision users |

Fix order I would suggest: A3 (the dial and cards must speak), A1 and A2 (a design decision on Paper and Ember), A7, A4, A5. Each fix updates its feature note and re-runs the matching test below.

## How to test, step by step

### 1. Dynamic Type (text size)
Why: text scales up to about 310 % at the top accessibility size. Layouts that clip or hide a control are bugs.
```bash
S=<simulator id>          # xcrun simctl list devices booted
xcrun simctl ui $S content_size large                                  # default
xcrun simctl ui $S content_size extra-extra-extra-large                # where rows start to stack (the app's threshold)
xcrun simctl ui $S content_size accessibility-extra-extra-extra-large  # the largest
```
All twelve categories, smallest to largest: `extra-small`, `small`, `medium`, `large`, `extra-large`, `extra-extra-large`, `extra-extra-extra-large`, `accessibility-medium`, `accessibility-large`, `accessibility-extra-large`, `accessibility-extra-extra-large`, `accessibility-extra-extra-extra-large`.

Then, **at each of default, xxxLarge and the largest**, walk this list. Take a screenshot with `xcrun simctl io $S screenshot file.png` (the Simulator tool's own screenshots can lag one action behind; sleep a second first):
- [ ] Idle compass; searching; search results; a place picked (Point); guiding (front card with END, next cards, ETA row); the pulled-up card list; arrival
- [ ] Profile: open a settings dropdown (it expands inline); add a friend; test logs buttons
- [ ] Store: themes, skins, the donate tiles
- [ ] Map tab and its four round buttons
- [ ] Sign in, sign up, and the code confirmation step
- [ ] The Find sheet ([[nearby-proximity]])
**Pass:** no text is cut off with no way to read it; every button is reachable (**END** always visible while guiding); nothing overlaps; scroll works where content is taller than the screen. **Fail:** anything else; fix with the app's two patterns: stack rows (`typeSize >= .xxxLarge` with an `if stacked { VStack } else { HStack }` inside a `Group`) or cap fixed-geometry chrome (`.dynamicTypeSize(...DynamicTypeSize.xxLarge)`).
Also test the iPhone SE size (the real test phone is a 4.7-inch SE 2nd gen) and the **watch** at its largest text size.

### 2. VoiceOver (screen reader)
On the device: Settings, Accessibility, VoiceOver (or triple-click the side button after setting the shortcut). In the simulator use Xcode, Open Developer Tool, **Accessibility Inspector**, pick the simulator, then *Run audit* and inspect each element's label, value, traits and hint.
Gestures: swipe right/left = next/previous element; double-tap = activate; three-finger swipe = scroll; two-finger tap = pause; rotor (twist two fingers) for headings, adjustable controls.
Walk the app **with the screen curtain on** (triple-tap with three fingers) so you cannot cheat:
- [ ] Can you tell, from speech alone, which tab you are on and how to change it?
- [ ] Search: do you hear the field, the results (name and distance), and the result you picked?
- [ ] Guiding: do you hear the next instruction, the distance and the ETA? **(Fails today: A3.)** Target: one element reading "Turn left in 120 metres, onto Smith Street. 8 minutes remaining."
- [ ] The dial: is there an element whose *value* is the bearing to the destination ("Destination ahead and to the right, 30 degrees")? **(Fails today: A3.)**
- [ ] The travel-mode carousel: swipe up/down on it changes mode and you hear the new one ([[travel-mode-carousel]] has the adjustable action)
- [ ] Every button has a label that says what it does ("End trip", not "xmark circle")
- [ ] Decorative graphics (needle art, glass rim) are hidden from VoiceOver
- [ ] Arrival is announced (post an `AccessibilityNotification.Announcement`)
- [ ] The Find sheet reads the distance and band
**Pass:** you could complete "search for a place and start guidance" with the screen curtain on. That is the standard.

### 3. Reduce Motion
Settings, Accessibility, Motion, Reduce Motion (simulator: same path; there is no `simctl` switch). Run a full trip start and end, a mode change, and the Find sheet.
**Pass:** no large movements, springs or spins; changes crossfade instead. **Today** only the carousel complies (A4). Implement with `@Environment(\.accessibilityReduceMotion)` and swap springs for `.easeOut(duration: 0.15)` or opacity.

### 4. Contrast, appearance and colour
```bash
xcrun simctl ui $S appearance dark      # and light
xcrun simctl ui $S increase_contrast enabled     # and disabled
```
- [ ] **Per theme (Ember, Tide, Paper, Arcade):** text over its background at least 4.5:1 (3:1 for 18.7 pt bold or 24 pt); icons and borders at least 3:1. Measure with the appendix script, or Accessibility Inspector's colour contrast calculator (Color tab). Re-run whenever a palette changes.
- [ ] **Outdoor test:** at full sun on a real phone, with brightness at auto, can you read the distance and the next turn? The Paper theme exists for this: check it first.
- [ ] **Differentiate Without Color:** Settings, Accessibility, Display & Text Size. The route colour (green on foot, blue driving) and needle red/grey must also be carried by shape, symbol or text. The carousel already pairs colour with a symbol; verify the route line and the off-route state.
- [ ] **Colour blindness:** Xcode's Accessibility Inspector has no filter; use the simulator's Settings, Accessibility, Colour Filters (protanopia, deuteranopia, tritanopia) and look at the dial and the cards.
- [ ] **Reduce Transparency / Bold Text:** switch each on; materials (the glass dial, the map buttons) must still read.

### 5. Touch targets and motor access
- [ ] Every control at least 44 by 44 pt (the map buttons are exactly 44). Check with Accessibility Inspector's *Hit area* overlay.
- [ ] One-handed reach: the primary actions (GUIDE, END, search) are in the lower half or reachable with the thumb on a 4.7-inch screen.
- [ ] **Voice Control:** Settings, Accessibility, Voice Control, then say "show numbers" or "show names". Every tappable thing needs a name or a number.
- [ ] **Switch Control / Full Keyboard Access:** every control focusable in a sensible order.
- [ ] No gesture is the *only* way to do something (the carousel has an adjustable action as the alternative).

### 6. Hearing and haptics
- [ ] Every audio cue has a visual one, and vice versa ([[audio-manager]], [[audio-cue-plan]]).
- [ ] The wrist: haptic patterns are distinct left versus right ([[watch-haptics]]); you can tell them apart while walking. This is the on-wrist blind test still pending.
- [ ] Phone with silent mode on: guidance still works visually.

### 7. Apple Watch
- [ ] Largest text size in Settings on the watch: the readouts stay readable ([[watch-app]]).
- [ ] VoiceOver on the watch reads the guidance arrow and distance.
- [ ] The proximity chip ([[nearby-proximity]]) is readable and the haptic ticks are noticeable.

## Recording a pass
Add a dated line to the **Manual checks** of the feature note you touched, and tick the matching box in the stage gate ([[P1 Stages and the MVP line]]). Format: `2026-10-09 accessibility-extra-extra-extra-large: idle, guiding, cards, Profile, Store, sign-in: pass`.

## Appendix: the contrast calculation
```python
def lum(h):
    c = [int(h[i:i+2], 16)/255 for i in (0, 2, 4)]
    c = [x/12.92 if x <= 0.03928 else ((x+0.055)/1.055)**2.4 for x in c]
    return 0.2126*c[0] + 0.7152*c[1] + 0.0722*c[2]
def ratio(a, b):
    hi, lo = sorted((lum(a), lum(b)), reverse=True)
    return (hi + 0.05) / (lo + 0.05)
```
Measured 2026-10-09 (values from `ThatWayUI/AppTheme.swift`):

| Theme | Ink on screen | Secondary text on screen | Text on accent | Accent on screen |
|---|---|---|---|---|
| Ember | 19.8 | 9.1 | **3.1** | 6.4 |
| Tide | 15.7 | 7.3 | 8.9 | 10.1 |
| Paper | 18.0 | 5.5 | **2.6** | **2.4** |
| Arcade | 17.5 | 9.0 | **3.5** | 5.7 |

Bold = below its bar. Guideline: 4.5 for normal text, 3.0 for large text and UI components.

Related: [[P6 Live testing]], [[P8 Before you push or commit]], [[compass-screen-layout]], [[theme-system]].
