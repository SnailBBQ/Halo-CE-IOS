"""The config.toml editor behind Settings > Multiplayer > Share maps (halo_toml_flags.h): edits one true/false key and leaves the rest of
the file exactly as it was. Compiles the real header with the system C compiler.
Run: python tools/tests/test_ios_toml_flags.py"""
import subprocess
import sys
import tempfile
from pathlib import Path

HOST = Path(__file__).resolve().parents[2] / "port/ios/HaloIOS"
C = r'''
#include <stdio.h>
#include "halo_toml_flags.h"
static int failures;
#define CHECK(c) do { if(!(c)) { printf("FAIL line %d: %s\n", __LINE__, #c); failures++; } } while(0)
static void set(const char *in, const char *section, const char *key, int v, int add, const char *want, int want_changed) {
    int changed = -1; char *out = halo_toml_set_bool(in, section, key, v, add, &changed);
    if (strcmp(out, want)) { printf("FAIL set:\n--- in\n%s\n--- got\n%s\n--- want\n%s\n", in, out, want); failures++; }
    if (changed != want_changed) { printf("FAIL changed=%d want %d for:\n%s\n", changed, want_changed, in); failures++; }
    free(out);
}
int main(void) {
    const char *file = "# my settings\n[display]\nvsync = true\n\n[network]\nmap_share = true  # host\nmap_seed = true\nmap_download = true\nmap_share_upload = 1024\n";
    CHECK(halo_toml_get_bool(file, "network", "map_share") == 1);
    CHECK(halo_toml_get_bool(file, "network", "map_seed") == 1);
    CHECK(halo_toml_get_bool(file, "network", "map_missing") == -1);
    CHECK(halo_toml_get_bool(file, "display", "map_share") == -1);
    CHECK(halo_toml_get_bool(file, "network", "map_share_upload") == -1);   /* a prefix is not the key */
    set(file, "network", "map_share", 0, 0, "# my settings\n[display]\nvsync = true\n\n[network]\nmap_share = false  # host\nmap_seed = true\nmap_download = true\nmap_share_upload = 1024\n", 1);
    set(file, "network", "map_share", 1, 0, file, 0);
    set("[network]\nmap_seed=true\n", "network", "map_seed", 0, 0, "[network]\nmap_seed=false\n", 1);
    set("network.map_share = true\n[display]\nvsync = true\n", "network", "map_share", 0, 0, "network.map_share = false\n[display]\nvsync = true\n", 1);
    /* absent: only added when asked */
    set("[network]\nmap_download = true\n", "network", "map_share", 0, 0, "[network]\nmap_download = true\n", 0);
    set("[network]\nmap_download = true\n", "network", "map_share", 0, 1, "[network]\nmap_share = false\nmap_download = true\n", 1);
    set("[display]\nvsync = true\n", "network", "map_share", 0, 1, "[display]\nvsync = true\n\n[network]\nmap_share = false\n", 1);
    set("", "network", "map_share", 1, 1, "\n[network]\nmap_share = true\n", 1);
    /* a commented line is not the key; other sections' same-named keys stay */
    set("[network]\n# map_share = true\n[other]\nmap_share = true\n", "network", "map_share", 0, 0, "[network]\n# map_share = true\n[other]\nmap_share = true\n", 0);
    /* Windows line endings survive */
    set("[network]\r\nmap_share = true\r\n", "network", "map_share", 0, 0, "[network]\r\nmap_share = false\r\n", 1);
    /* no trailing newline */
    set("[network]\nmap_share = true", "network", "map_share", 0, 0, "[network]\nmap_share = false", 1);
    /* quoted text values (voice chat mode) */
    char word[32];
    CHECK(halo_toml_get_string("[audio]\nvoice_chat = \"open_mic\"  # x\n", "audio", "voice_chat", word, sizeof word) && !strcmp(word, "open_mic"));
    CHECK(!halo_toml_get_string("[audio]\nvolume = 1\n", "audio", "voice_chat", word, sizeof word));
    CHECK(halo_toml_get_string("audio.voice_chat = \"off\"\n", "audio", "voice_chat", word, sizeof word) && !strcmp(word, "off"));
    { int c = -1; char *o = halo_toml_set_string("[audio]\nvoice_chat = \"push_to_talk\"  # keep\nvolume = 1\n", "audio", "voice_chat", "open_mic", 0, &c);
      CHECK(!strcmp(o, "[audio]\nvoice_chat = \"open_mic\"  # keep\nvolume = 1\n") && c == 1); free(o); }
    { int c = -1; char *o = halo_toml_set_string("[audio]\nvoice_chat = \"off\"\n", "audio", "voice_chat", "off", 0, &c);
      CHECK(!strcmp(o, "[audio]\nvoice_chat = \"off\"\n") && c == 0); free(o); }
    { int c = -1; char *o = halo_toml_set_string("[audio]\nvolume = 1\n", "audio", "voice_chat", "open_mic", 1, &c);
      CHECK(!strcmp(o, "[audio]\nvoice_chat = \"open_mic\"\nvolume = 1\n") && c == 1); free(o); }
    { int c = -1; char *o = halo_toml_set_string("[display]\na = 1\n", "audio", "voice_chat", "off", 1, &c);
      CHECK(!strcmp(o, "[display]\na = 1\n\n[audio]\nvoice_chat = \"off\"\n") && c == 1); free(o); }
    { int c = -1; char *o = halo_toml_set_string("[audio]\nvoice_chat = \"off\"\n", "audio", "voice_chat", "open_mic", 0, &c);
      CHECK(!strcmp(o, "[audio]\nvoice_chat = \"open_mic\"\n") && c == 1); free(o); }
    printf(failures ? "FAILED\n" : "OK\n");
    return failures != 0;
}
'''
with tempfile.TemporaryDirectory() as tmp:
    src = Path(tmp) / "t.c"
    src.write_text(C)
    exe = Path(tmp) / "t"
    build = subprocess.run(["cc", "-std=c11", "-Wall", "-Wextra", "-Werror", f"-I{HOST}", str(src), "-o", str(exe)], capture_output=True, text=True)
    if build.returncode:
        print(build.stderr)
        sys.exit(1)
    run = subprocess.run([str(exe)], capture_output=True, text=True)
    print(run.stdout)
    if run.returncode:
        sys.exit(1)
print("PASS: config.toml true/false editor changes only the wanted key (sections, dotted keys, comments, CRLF, absent keys)")
