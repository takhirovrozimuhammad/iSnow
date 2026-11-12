# iSnow · Ridzhan edition

A native macOS winter studio with a midnight blue and violet interface, original snow-pearl artwork, low-distraction work mode and snow you can shape with your own hands.

Requires macOS 14 or later. Builds for Apple silicon and Intel with Swift 6 and no third-party dependencies.

## Make your own snowman

1. Open **Qor ustaxonasi** in settings and click **Yangi qor to‘kish** for a fresh strip of snow.
2. Hold **Option** and move through visible snow. The gathered snow becomes a growing ball. Empty air produces nothing.
3. Release Option to drop the ball. Make three balls; more snow makes a larger ball.
4. Drag the middle ball above the base, then the head above the middle. The blue ring shows where it will snap. Three stacked balls become an animated snowman.
5. Drag your snowman onto a window or beside the Dock. It falls when its supporting window moves. Click it to knock snow off.

**Option + Shift** keeps the shovel available. The full-screen overlay stays click-through; only the visible balls and snowmen catch clicks. Fullscreen hides creations and their click panels, and restores them afterwards.

## Build and install

```sh
git clone https://github.com/takhirovrozimuhammad/iSnow.git
cd iSnow
git checkout ridzhan-winter-studio
swift test
./build.sh --install
```

The new app uses the independent bundle identifier `uz.ridzhan.isnow`. Launch at login and Accessibility permission therefore belong to this edition. Accessibility lets the app find the exact Dock and desktop-icon positions; Screen Recording is not required.

Work mode caps the effective snow count, density and frame rate and stops automatic characters without overwriting the saved sliders. Battery saver is also available. The app runs locally and does not send screen content anywhere.

## Build verification

GitHub Actions runs the workshop physics and fullscreen regression tests, builds a universal app, renders every actual settings page in a native AppKit window, verifies code signing, and packages a ZIP and DMG. The generated previews are in the build artifact. An ad-hoc signature is used unless you build with your own Apple Development certificate; this distribution is not Apple-notarized.

## Attribution and license

This customized distribution is based on [iSnow by Filip Hajduch](https://github.com/filiphajduch420/iSnow), released under the MIT License. The original copyright and license remain in [LICENSE](LICENSE), and both LICENSE and [NOTICE.md](NOTICE.md) are included in the app bundle. Interface, original artwork and the hands-on workshop were added for the Ridzhan edition. This project is not endorsed by the upstream author.

## Window snow in 2.1

Settings → Qor qatlamlari → Oynalarga enables snow on regular app windows, including iSnow’s settings window. To‘planishni sinash adds a visible layer immediately for a quick check. Fullscreen windows do not collect snow. Moving a window, even slowly, releases its drift at its old position; released clumps can land on lower windows, but cannot reattach to the source window. Closing multiple windows releases their snow too. Space switches preserve it. Dock preferences are unchanged.
