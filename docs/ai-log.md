# AI usage log (working notes)

Scratch file. Captured as things happen, distilled into `solutions.md` at the end.
Rule for this file: write the entry **when it happens**, not from memory later.

## Tools used

| Tool | Used for |
|---|---|
| Claude (Claude Code, in VS Code) | Reading the starter codebase, forming initial hypotheses on all seven tickets, driving the emulator over adb, drafting fixes and tests, reviewing my own diffs |

Everything below is a case where an AI answer was wrong or would have led me somewhere
wrong. Each entry records the claim, how I caught it, and what I did instead.

---

## Slip 1 — "`JAVA_HOME` controls the JDK that Gradle uses"

**Claim.** While setting up the toolchain, Claude asserted that passing
`JAVA_HOME` per command was the correct way to give the Android build JDK 17, and
that `flutter config --jdk-dir` should be avoided because it writes a user-global
setting. It was confident enough that I ran the build on that basis.

**What actually happened.** The build failed:

```
Execution failed for task ':path_provider_android:compileDebugJavaWithJavac'.
> Could not resolve all files for configuration ':path_provider_android:androidJdkImage'.
   > Failed to transform core-for-system-modules.jar ...
      > Error while executing process
        /Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/jlink
```

The `jlink` path names **Android Studio's bundled JBR**, not the JDK I had exported.

**How I caught it.** Rather than accept a second guess, I read the resolution order
in the pinned SDK itself —
`~/fvm/versions/3.27.0/packages/flutter_tools/lib/src/android/java.dart`, in
`_findJavaHome`:

```dart
final Object? configured = config.getValue('jdk-dir');   // 1. wins
if (configured != null) return configured as String;
final String? androidStudioJavaPath = androidStudio?.javaPath;  // 2.
if (androidStudioJavaPath != null) return androidStudioJavaPath;
final String? javaHomeEnv = platform.environment[...];   // 3. never reached
```

`JAVA_HOME` sits *below* Android Studio's JBR. My Android Studio bundles JBR
**21.0.10**, and AGP below 8.2.1 with Java 21+ hits a known Google bug
(issuetracker 294137077) that fails exactly at the `core-for-system-modules.jar`
transform. So the suggested approach could never have worked, and the failure was
not random.

**What I did instead.** `flutter config --jdk-dir=<jdk17>`, which is the only entry
that outranks the bundled JBR. Verified with `flutter doctor -v` reporting
`Java version ... 17.0.20.1`.

**Takeaway.** The lesson isn't "the AI was wrong about a flag". It's that the
authoritative answer was sitting in the pinned SDK source the whole time, and
reading it took less time than the failed build did.

---

## Slip 2 — "RES-106 is fixed by calling `.toLocal()` before formatting"

**Claim.** In the first pass over the tickets, Claude diagnosed RES-106 as
`DateTime.parse` returning a UTC instant that `DateFormat.format` then prints in
UTC, and gave the fix as: call `.toLocal()` before formatting.

**Why that's misleading.** The first half is correct; the prescription is not. The
simulated backend builds its pickup windows in **Asia/Bangkok (UTC+7)** —
`_marketUtcOffsetHours = 7` in `fake_api_service.dart`, and every store is at
lat 13.75 / lng 100.5. My device is **Asia/Karachi (UTC+5)**. So for the ticket's
own example, a bakery open 06:00–09:30 Bangkok:

| | Displayed |
|---|---|
| Unfixed (prints UTC) | 23:00 – 02:30 |
| After `.toLocal()` on a UTC+5 device | 04:00 – 07:30 |
| Store's actual posted hours | 06:00 – 09:30 |

`.toLocal()` makes the number move, so it *looks* fixed, but it is only correct
when the user's device happens to be in the market's timezone. It trades "always
wrong" for "wrong for anyone outside Bangkok" — including me, working from
Pakistan.

**How I caught it.** Checked the emulator's zone (`adb shell getprop
persist.sys.timezone` → `Asia/Karachi`) before writing any formatting code, and
compared what `.toLocal()` would print against the hours the ticket says the shop
actually keeps.

**What I did instead.** Treated RES-106 as a product question — whose clock should
a pickup time be shown in? — rather than a one-line change. Reasoning and the
decision are in `solutions.md` under RES-106.

**Takeaway.** The AI's *diagnosis* was sound and its *fix* was a plausible-looking
shortcut. Those are separable, and the fix is the half that needed checking against
real data.

---

## Running notes

<!-- Append new entries here as they happen. Keep the claim / caught / did-instead shape. -->
