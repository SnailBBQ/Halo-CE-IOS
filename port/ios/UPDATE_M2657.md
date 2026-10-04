# M2.6.57 — Universal build 95 and local campaign co-op

Integrates [Universal build 95](https://github.com/cybersecurity/halo-ce-universal/releases/tag/build-95), including its two-player campaign menus, profile selection and local controller assignments.

## Play together

Connect controllers before choosing Multiplayer → Co-op Campaign. With one physical controller, player one uses touch and player two uses that controller. With two physical controllers, the first controls player one and the second controls player two. Choose player two’s profile with player two’s controller, then choose a level and difficulty. Automatic touch visibility keeps player one’s controls available with one controller.

This is local split-screen campaign co-op. It does not add online campaign co-op. Co-op starts a level rather than continuing a single-player checkpoint. Campaign cheats and the native settings remain scoped to the primary player; they are not a separate player-two editor.

Controller ownership is captured on entering co-op, so unplugging one controller does not silently move the other player’s inputs. Rumble is routed separately. Main-menu/single-player resets restore normal input routing.

## Preserved behavior

Existing private/public multiplayer discovery, Xbox map imports, on-device XISO extraction, mods, backups and profiles remain available. Regular and Mod Test apps remain separate. The guest ELF loader, pointer mapping and signing are unchanged.

## Validation

Portable routing checks cover zero, one and two controllers, including a controller in the second hardware slot. Existing extraction and source checks are run alongside Apple CI. Device validation must cover player-two profile selection, campaign progression, disconnect/reconnect, rumble, touch visibility and single-player return. Neither co-op performance nor device correctness is claimed before those checks.
