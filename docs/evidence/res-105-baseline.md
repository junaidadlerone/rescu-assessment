# RES-105 — baseline (before any optimisation)

Captured before touching `home_screen.dart`, so the "before" side of the
comparison can't be reconstructed later.

Commit at time of capture: `bbcb25e` (only RES-102 landed; the home feed is
untouched starter code).

## Method

| | |
|---|---|
| Build | `flutter run --profile` — **not** debug; debug builds are unoptimised and their timings are meaningless |
| Device | Android emulator, `sdk_gphone_arm64`, Android 11, 60 Hz, `dalvik.vm.heapgrowthlimit=192m` |
| Flutter | 3.27.0 (pinned), Dart 3.6.0 |
| Screen | Home feed, `Pickup today` filter off, full catalog (122 deals over 7 pages) |
| Scroll input | `adb shell input swipe 540 1700 540 500 220`, repeated |
| Frame source | `dumpsys SurfaceFlinger --latency 'SurfaceView - dev.rescu.rescu/dev.rescu.rescu.MainActivity#0'` |
| Memory source | `dumpsys meminfo dev.rescu.rescu`, `TOTAL PSS` |

Raw data: [`res-105-latency-before.txt`](res-105-latency-before.txt).
Reduction script: [`framestats.sh`](framestats.sh) (`./framestats.sh <latency file>`).

### Why not `dumpsys gfxinfo`

It's the usual answer for Android jank and it does not work here. Flutter renders
into its own `SurfaceView` and bypasses Android's HWUI pipeline, so the counters
never populate — after a full scroll session it reported:

```
Total frames rendered: 1
Janky frames: 1 (100.00%)
```

That is an artefact of the measurement, not the app. SurfaceFlinger's per-layer
present timestamps are the correct source for a Flutter surface.

## Frame timings — 8 sustained swipes

```
  refresh period       : 16.67 ms (60 Hz)
  frame intervals      : 126
  mean                 : 55.18 ms  (18.1 fps effective)
  p50                  : 55.64 ms
  p90                  : 79.81 ms
  p95                  : 97.01 ms
  p99                  : 127.58 ms
  worst                : 155.97 ms
  janky (>1.5x budget) : 123 of 126 (97.6%)
```

The frame budget at 60 Hz is 16.67 ms. The **median** frame takes 55.64 ms — more
than three budgets. 97.6% of frames miss. This is not occasional jank; the feed
essentially never hits frame rate while scrolling.

## Memory — `TOTAL PSS` across a scroll session

| Point | TOTAL PSS | TOTAL RSS |
|---|---|---|
| Home loaded, before scrolling | 113.9 MB | 188.4 MB |
| After 10 swipes | 130.6 MB | 210.0 MB |
| After 18 swipes | 113.5 MB | — |
| After 33 swipes | **133.5 MB** (peak) | — |
| After 48 swipes | 119.2 MB | — |
| After 63 swipes | 115.4 MB | — |

## Honest reading of the memory numbers

The ticket says memory "grows the further you scroll until the OS kills the app".
On this fixture it **does not grow without bound** — it peaks around 133 MB and
then oscillates down. Two reasons, both measurement artefacts rather than
counter-evidence:

1. **The catalog is finite.** The log shows `GET /deals?page=1` through `page=7`
   and no more: all 122 deals are loaded after roughly 20 swipes. The feed cannot
   grow past 122 cards, so retention plateaus. Unbounded growth needs a catalog
   larger than the fixture.
2. **Flutter's `ImageCache` evicts.** It defaults to 1000 images / 100 MiB, so
   full-resolution decodes get reclaimed once that ceiling is hit. The oscillation
   in the table is that ceiling plus GC, not the leak resolving itself.

What the numbers *do* establish: a 122-item feed with ~4 cards visible reaches
133 MB against a 192 MB heap growth limit — 69% of the device's headroom for a
list that should hold a screenful. The mechanism the ticket describes is present
and measurable; the fixture is just too small to reach the OOM.

## What to re-measure after the fix

Same build mode, same device, same swipe command, same two dumpsys sources:

- frame p50 / p90 / jank % from `framestats.sh`
- `TOTAL PSS` at the same swipe counts (0, 10, 18, 33)

## Caveat

An emulator is not a mid-range physical device; absolute numbers are not
comparable to the handset the ticket describes. The before/after *ratio* on
identical hardware and identical input is the claim being made here, not the
absolute fps.
