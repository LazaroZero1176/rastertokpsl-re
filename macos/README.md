# macOS support

Build and install `rastertokpsl-re` on macOS, including Apple Silicon.

## Why this is needed

Kyocera's FS-10xx series are GDI printers: they contain no interpreter,
so every page must be converted to KPSL on the host. CUPS does that by
running a separate filter binary for each job.

Kyocera's build of that filter dates from 2013 and contains no ARM code:

```
$ lipo -archs /Library/Printers/Kyocera/kpsl/rastertokpsl.app/Contents/MacOS/rastertokpsl
x86_64 i386 ppc7400
```

On Apple Silicon it therefore runs only under Rosetta 2. Apple removes
Rosetta from macOS 28 onwards, and macOS 27 uninstalls it during the
upgrade. After that the queue accepts jobs and prints nothing.

Because `rastertokpsl-re` ships as source, it can simply be compiled for
arm64. The build script produces a universal binary, so the same tree
works on Intel Macs too.

## Requirements

Xcode Command Line Tools only:

```
xcode-select --install
```

No CMake and no Homebrew are needed -- the CUPS headers and libraries
ship with the macOS SDK.

## Install

```bash
./macos/build.sh
sudo ./macos/install.sh
```

`install.sh` patches the bundled PPD to point at the installed filter,
then switches an existing Kyocera queue over to it. If no queue exists,
it looks for the printer and creates one.

Pick a different model with `--model`:

```bash
sudo ./macos/install.sh --model FS-1060DN
```

Available models are the PPDs in the repository root. The FS-1041 uses
the FS-1040 PPD.

## Uninstall

```bash
sudo ./macos/uninstall.sh
```

## Files

| Path | Purpose |
|------|---------|
| `/Library/Printers/Kyocera-RE/rastertokpsl-re` | the filter |
| `/Library/Printers/PPDs/Contents/Resources/Kyocera_*GDI-RE.ppd` | patched PPD |

Nothing inside Kyocera's own driver bundle is modified, so the original
installation stays intact and `uninstall.sh` can fall back to it.

## Verification

Tested on macOS 26.7, Apple M3 Pro, with a Kyocera FS-1041 shared over
USB from an AirPort base station.

Feeding the same CUPS raster to Kyocera's filter and to this one
produces output of identical length. Within the page data the two differ
only in how one value is encoded -- the original pads it to seven bytes,
this implementation writes the same value in four and declares the
shorter length. Both are self-consistent, and printed pages are
indistinguishable.

The header differs in a way that favours this implementation. With a job
title containing non-ASCII characters (here `Größe`):

```
original:  c3ff b6ff c3ff 9fff     UTF-8 bytes padded with 0xFF
this one:  f600 df00               ö and ß correctly in UTF-16LE
```

That is the encoding bug this project was written to fix, and it is
present in the macOS build of the original filter as well.

Using the FS-1040 PPD from this repository instead of Kyocera's macOS
PPD produces byte-identical output apart from the embedded timestamp.

## Notes

The binary is not code-signed or notarized. It is built locally, so
Gatekeeper does not apply; do not ship prebuilt copies over the web
without signing them.

If your printer is shared from an AirPort base station over
`_riousbprint`, note that this protocol serves one client at a time and
offers no AirPrint. A "printer is busy" state is unrelated to this
filter -- clear queues on other Macs, or restart the base station.
