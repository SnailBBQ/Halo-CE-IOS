"""Regression checks for recoverable Custom Edition map-load failures."""
from pathlib import Path
import plistlib

ROOT = Path(__file__).resolve().parents[2]
main = (ROOT / "source/main/main.c").read_text()
cache = (ROOT / "source/cache/cache_files.c").read_text()
runner = (ROOT / "port/ios/HaloIOS/halo_guest_runner.m").read_text()
with (ROOT / "port/ios/HaloIOS/Info.plist").open("rb") as stream:
    info = plistlib.load(stream)

start = main.index("static void main_new_map(\n\tstruct game_options *options)\n{")
end = main.index("\nstatic void main_change_map_name(", start)
load = main[start:end]
assert "if (game_load(options))" in load
assert "scenario_unload();" in load
assert "errors_handle();" in load
assert "returning to the main menu" in load
assert "main_globals.want_to_be_at_main_menu = TRUE;" in load
assert "main_globals.defer_map_change = FALSE;" in load
assert "#ifdef HALO_IOS_GUEST" in load and "#else\n\t\terror(_error_immediate, \"game_load() failed.\");\n#endif" in load
assert "if (loading_main_menu)" in load and 'error(_error_immediate, "main menu scenario failed to load.");' in load
assert 'error(_error_immediate, "game_load() failed.")' not in load.split("#else", 1)[0]
assert 'error(_error_immediate, "game_load() failed.")' in load

unload_start = cache.index("void scenario_tags_unload(")
unload_end = cache.index("\n/* port: the loaded tags' table", unload_start)
unload = cache[unload_start:unload_end]
assert "#ifdef HALO_IOS_GUEST" in unload
assert "else if (cache_file_globals.tags_loaded && cache_file_globals.tag_header)" in unload
assert "cache_file_globals.tag_header = NULL;" in unload
assert "snapshot budget 48 MiB" in runner
assert "snapshot budget 8 MiB" not in runner
assert info["CFBundleShortVersionString"] == "0.2.123"
assert info["CFBundleVersion"] == "2723"
assert info["HaloSourceMilestone"] == "M2.6.123"
print("PASS: rejected map loads clean up and return to menu; tag-header cleanup is guarded; diagnostics and identity match M2.6.123")
