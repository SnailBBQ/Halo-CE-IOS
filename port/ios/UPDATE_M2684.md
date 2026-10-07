# M2.6.84 — Non-Jailbreak execution boundary diagnostics

Regular app **0.2.84 / 2684**. The Mod Test app derives **0.2.84.1 / 268401**. The engine remains **OpenCE build 138** (`76addf661f02e2fd090d7b00f9dd12c29e562a9b`), **network version 20**, with the same 20 MiB game-state capacity and Apple OpenGL ES renderer as M2.6.83.

M2.6.83 passed GitHub Actions and is the new build-138 compile baseline. This update does not change Regular or Mod Test runtime behavior. It extends only the **Non-Jailbreak Version** so the next device tests can distinguish an address-space failure from an executable-code failure.

## Why this update

Two stock/free-signed devices have shown different boundaries:

- The earlier iPhone 14 Plus / iOS 16.2 test could reserve 4 GiB in general but could not obtain a usable 4-GiB-aligned guest window. The existing `Flexible 4 GiB ANYWHERE` probe remains for that case.
- A tester's iPhone 16 Pro Max (`iPhone17,2`) / iOS 27.2, also without Extended Virtual Addressing or Increased Memory Limit, let the kernel place a 4-GiB-aligned arena at `0x7000000000`. It loaded all 24 maps, reconstructed `ui.map` scenario/BSP/global state, loaded the real guest ELF, set up TLS and resolved all 233 host imports, then the process disappeared after the last persistent step `guest entering __guest_start`.

That second result means address-space allocation is not the only Non-Jailbreak problem. M2.6.84 adds a much narrower execution trace around the real guest handoff.

## Non-Jailbreak execution canary

After the existing aligned guest arena and PAGEZERO bridge are ready, the Non-Jailbreak host now temporarily uses guest VA `0x0FFF0000` for an execution canary. It:

1. commits one real guest-arena page RW with `halo_guest_commit()`;
2. writes two known AArch64 instructions (`movz w0,#0x4841; ret`);
3. invalidates that instruction range with `sys_icache_invalidate()`;
4. changes the page to RX with the same `halo_guest_protect()` path used by the real ELF;
5. records a persistent phase immediately before instruction fetch;
6. calls the canary and expects `0x4841` back;
7. records the return result and decommits the page before Halo starts.

This is not JIT enablement and it does not bypass code signing. It is a diagnostic using the same guest-arena RW→RX mechanism the current loader already relies on. If stock iOS terminates the app on that instruction fetch, the next launch should preserve `nonjb 403 exec canary entering` in `start-history.txt`.

## Persistent execution breadcrumbs

The Non-Jailbreak Version now flushes numbered startup phases to `launch-phase.txt` around the handoff:

- **401** — PAGEZERO guest execution bridge installed.
- **402** — guest-arena canary being mapped/prepared.
- **403** — about to fetch the first canary instruction.
- **404** — canary returned to the host.
- **405** — the real `halo_guest.elf` executable pages are RX-protected.
- **408** — the 16 MiB guest main stack is committed.
- **410** — the main guest host thread is running on that stack.
- **411** — the guest execution guard is armed.
- **412** — the real `__guest_start` host pointer is resolved.
- **413** — the host is branching into real `__guest_start`.
- **416** — guest execution reached the first main-thread `host_set_tp` import from inside guest startup.
- **418** — `__guest_start` unexpectedly returned to the host.

The first `host_set_tp` marker is especially useful: if **416** is reached, real guest instructions executed far enough to initialize the guest thread and cross back through a host import. If the last step remains **413**, the failure is before that boundary.

The `nonjb ...` phases are treated as startup phases by the existing Safe Start/history logic, so reopening the app does not erase where a silent termination happened.

## What did not change

- No arbitrary-base guest is enabled yet. The flexible 4 GiB reservation remains **diagnostic only**.
- Regular and Mod Test do not compile the execution-canary/trace code.
- No ANGLE/Metal work was added; rendering remains Apple OpenGL ES.
- OpenCE stays build 138 / network 20.
- No save, backup, map, XISO, multiplayer, input or gameplay behavior is intentionally changed.
- Existing automatic engine-change `.halobackup` protection remains unchanged.

## Validation

Local checks cover the canary instruction bytes and RW→RX sequence, numbered phase ordering, first-host-import marker, flag isolation, launch-history classification, build identity and strict OpenCE build-138 flags-off equivalence. GitHub Actions remains authoritative for the Apple host compile and IPA packaging.

## Device checklist

1. Build **Non-Jailbreak Version** from M2.6.84 and install the same way as the previous free-signed test.
2. On the iPhone 14 Plus, capture the `Flexible 4 GiB ANYWHERE` line and confirm whether the normal aligned arena still fails before execution tracing starts.
3. On the iPhone 16 Pro Max, launch once. If the app disappears, reopen it and use **Copy logs** or **Share logs** immediately.
4. Send `start-history.txt`, `launch-phase.txt`, and `ios-boot.log`. The most important item is the last `nonjb NNN ...` phase.
5. If the last phase is 403, also collect the matching iOS Analytics `.ips`/`JetsamEvent` if available. If it reaches 404 but stops at 413, the guest-arena execution canary works and the failure is specific to real guest startup. If it reaches 416, real guest execution and the first host-import round trip both work and the next investigation moves deeper into musl/constructors/main.

M2.6.84 is still an **experimental Non-Jailbreak diagnostic**, not a claim of free-signing support.
