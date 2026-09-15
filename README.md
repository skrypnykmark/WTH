# WTH (What the HEIC?)

WTH is a small macOS menu-bar app that watches
your Downloads folder and automatically converts AirDropped HEIC photos to
JPEG.

## Why I built this

I prefer to keep photos on my iPhone in HEIC because HEIC provides excellent
image quality while using less storage space than traditional formats such as
JPEG. However, when I AirDrop photos from my iPhone to my Mac, I usually want a
more universally compatible format such as JPEG for editing, uploading, and sharing.

This utility lets me keep the original HEIC photo exactly as it is while
automatically creating a JPEG copy when the image arrives on my Mac. That way I
get the storage and quality benefits of HEIC on my phone while having an
immediately usable JPEG on my Mac.

Both files are kept. When `IMG_1234.HEIC` lands in `~/Downloads`, WTH
writes a JPEG next to it and leaves the original alone:

```
IMG_1234.HEIC   the original photo, never modified or deleted
IMG_1234.jpg    created automatically by WTH
```

If a JPEG with the same name already exists, WTH leaves it alone and skips
that file instead of overwriting it.

## What it does

- Lives in the menu bar.
- Watches `~/Downloads` for new `.heic` / `.heif` files (case-insensitive).
- Waits for a file to finish copying before converting, so an AirDrop that is
  still in progress never becomes a truncated JPEG.
- Saves a high-quality JPEG with the same base name
  (`IMG_1234.HEIC` → `IMG_1234.jpg`).
- Keeps EXIF, GPS, TIFF, IPTC, and the embedded color profile, and bakes in the
  EXIF orientation so the JPEG looks right everywhere.
- Keeps the original HEIC and never overwrites an existing JPEG.
- Also converts HEIC files you pick yourself, from anywhere on your Mac.
- Converts each photo as soon as it lands in the folder.
- Has a toggle for automatic conversion and an optional Launch at Login.
- Has no third-party dependencies.

## Requirements

- macOS 13 Ventura or later (Apple Silicon or Intel).
- To build from source: Xcode 16 or later (the project uses Swift 6).

## Building

```sh
git clone https://github.com/skrypnykmark/WTH.git
cd WTH
open WTH.xcodeproj
```

Select the **WTH** scheme and press Run (⌘R). Or build from the command
line:

```sh
xcodebuild -project WTH.xcodeproj \
  -scheme WTH \
  -configuration Release \
  -destination 'platform=macOS' build
```

If you want to use Launch at Login, copy the built app into `/Applications`
first, since login items work best from a stable location:

```sh
cp -R ~/Library/Developer/Xcode/DerivedData/WTH-*/Build/Products/Release/WTH.app /Applications/
```

## Usage

1. Launch the app.
2. Click the menu-bar icon and turn on **Launch at Login** if you want it.
3. Leave **Automatic Conversion** on.
4. AirDrop HEIC photos from your iPhone to your Mac.
5. The HEIC files arrive as usual, and a JPEG appears beside each one shortly
   after.

The menu also has:

- **Choose HEIC Files…** — pick any HEIC file on your Mac, wherever it lives,
  and convert it to JPEG. When it finishes, the folder opens in Finder with the
  new JPEGs selected.
- **Convert Existing HEIC Files Now** — scans `~/Downloads` and converts any
  HEIC files that don't already have a JPEG.
- **Open Downloads Folder**.
- The last conversion time and a Quit button.

## Permissions

WTH asks for as little as it can:

| Permission | Why it's needed |
| --- | --- |
| **Files and Folders › Downloads** | To notice new HEIC files and write the JPEG beside them. macOS asks the first time the app reads your Downloads folder. |

The app isn't sandboxed, since it runs outside the Mac App Store and needs to
watch a folder. It only asks for Downloads through macOS privacy protection
(TCC); it doesn't need Full Disk Access. If you deny the prompt, open
**System Settings › Privacy & Security › Files and Folders**, enable WTH,
and click **Check Again** in the menu.

## Privacy

Everything happens locally. There are no accounts, no cloud service, no
telemetry, and no analytics. The app never uploads anything and doesn't need an
internet connection. The original HEIC file is never deleted or modified.

## How it works

The app is a thin SwiftUI menu bar on top of a separate core framework so the
interesting logic can be tested on its own.

```
AirDrop → ~/Downloads/*.HEIC
             │
             ▼
    DownloadsWatcher      file-system events + a periodic scan
             │
             ▼
    ConversionEngine      dedupes, checks policy, reports results
             │
             ▼
    FileStabilityChecker  waits until the copy is finished
             │
             ▼
    ImageConverter        ImageIO → JPEG, metadata preserved
             │
             ▼
        IMG_1234.jpg      (original IMG_1234.HEIC untouched)
```

- `WTHCore` holds the logic: the directory watcher, the stability check, the
  converter, and the conversion engine.
- `WTH` holds the menu-bar UI and wires everything together.

## Tests

The unit tests cover file detection, filename handling, duplicate handling,
stability detection, conversion and metadata preservation, JPEG quality,
orientation, and the directory watcher.

```sh
make test
```

## Uninstall

1. Open the menu, turn off **Launch at Login**, and choose **Quit**.
2. Delete the app:

   ```sh
   rm -rf /Applications/WTH.app
   ```

3. Remove its preferences if you like:

   ```sh
   defaults delete com.wth.app
   ```

JPEGs that were already created stay in your Downloads folder. Delete them if
you don't want them.

## License

[MIT](LICENSE)
