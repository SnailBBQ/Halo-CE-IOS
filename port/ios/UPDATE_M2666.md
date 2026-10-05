# M2.6.66 — sound lifecycle safety

Universal baseline remains build 98. Official and Mod Test share this guest fix.

The supplied M2.6.65 multiplayer log ends with the software-reference assertion
in sound_cache_sound_finished (original source line 263). It does not record
which release caller caused the mismatch, so the exact device failure is not
fully reproduced or attributed yet.

A confirmed lifetime defect exists during looping-sound definition replacement:
sound_set_definition_end can enforce channel limits by stopping and deleting
its own sound. The looping update continued using that datum, and the enclosing
channel update could read it again for speech processing. iOS callers now exit
that update when its channel loses the sound, before reading or queueing more
permutations. Other-channel preemption and normal live updates are preserved.
The cache underflow assertion remains; an unexpected mismatch logs its block,
tag, loaded/initialized flags, hardware references and release caller address.

Regression: python tools/tests/test_ios_sound_lifecycle.py compiles the actual
replacement function and caller guard, exercising normal continuation,
self-preemption through both limits, and preemption of another channel.
Existing source, declarations and upstream 98 checks also run.

Device validation: repeat multiplayer joining, weapon charging/loops, deaths,
map changes and leaving a server; repeat campaign audio. Collect debug.txt and
ios-boot.log immediately if a halt occurs. This fixes a demonstrated lifetime
bug; it does not claim the reported assertion is conclusively resolved until
these tests pass. Signing compatibility remains unproven and is a separate test.
