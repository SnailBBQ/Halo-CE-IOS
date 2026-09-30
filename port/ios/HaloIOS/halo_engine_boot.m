#import "halo_engine_boot.h"

#include "halo_cache_runtime.h"
#include "halo_guest_runtime.h"

#include <stdint.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>

#define HALO_SCENARIO_STRUCTURE_BSP_BLOCK_OFFSET UINT32_C(0x5A4)
#define HALO_SCENARIO_TYPE_OFFSET                UINT32_C(0x3C)
#define HALO_TAG_INSTANCE_SIZE                   UINT32_C(0x20)
#define HALO_SCENARIO_BSP_REFERENCE_SIZE         UINT32_C(0x20)

#define HALO_SCENARIO_GROUP UINT32_C(0x73636E72) /* 'scnr' */
#define HALO_STRUCTURE_BSP_GROUP UINT32_C(0x73627370) /* 'sbsp' */
#define HALO_GAME_GLOBALS_GROUP UINT32_C(0x6D617467) /* 'matg' */

static void say(void (^line)(const char *), const char *fmt, ...)
{
    char buffer[1024];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(buffer, sizeof(buffer), fmt, ap);
    va_end(ap);
    line(buffer);
}

static uint16_t read_u16le(const uint8_t *p)
{
    return (uint16_t)(p[0] | ((uint16_t)p[1] << 8));
}

static uint32_t read_u32le(const uint8_t *p)
{
    return ((uint32_t)p[0]) |
           ((uint32_t)p[1] << 8) |
           ((uint32_t)p[2] << 16) |
           ((uint32_t)p[3] << 24);
}

static void write_u32le(uint8_t *p, uint32_t value)
{
    p[0] = (uint8_t)value;
    p[1] = (uint8_t)(value >> 8);
    p[2] = (uint8_t)(value >> 16);
    p[3] = (uint8_t)(value >> 24);
}

static int guest_pointer_sane(uint32_t va, uint32_t size)
{
    if (!va || !size)
        return 0;
    return halo_guest_ptr(va, size) != NULL;
}

/*
 * This is the first source-derived engine entry stage. It mirrors the recovered
 * scenario_load() -> scenario_switch_structure_bsp(0) data path using the
 * original 32-bit Xbox layouts already resident in the translated guest space.
 *
 * It deliberately does not claim to execute game_initialize_for_new_map().
 * That function fans out through rasterizer, audio, input, objects, AI, scripts,
 * timing and other platform-dependent engine modules. Those modules must be
 * brought across with a real iOS platform/runtime layer rather than stubbed if
 * the goal is an authentic game boot.
 */
int halo_ios_engine_boot_main_menu(void (^line)(const char *text),
                                   halo_ios_engine_boot_result *result)
{
    memset(result, 0, sizeof(*result));

    const uint32_t scenarioBase = halo_ios_cache_scenario_base_va();
    const uint32_t scenarioDatum = halo_ios_cache_scenario_tag_index();
    const uint32_t tagInstancesVA = halo_ios_cache_tag_instances_va();
    const uint32_t tagCount = halo_ios_cache_tag_count();

    line("");
    line("=== RECOVERED ENGINE ENTRY: scenario_load(levels\\ui\\ui) ===");

    if (!scenarioBase || !guest_pointer_sane(scenarioBase, 0x5B0))
    {
        line("ENGINE BLOCKED: scenario base pointer is unavailable.");
        return 0;
    }

    uint8_t *scenario = halo_guest_ptr(scenarioBase, 0x5B0);
    result->scenario_base_va = scenarioBase;
    result->scenario_type = read_u16le(scenario + HALO_SCENARIO_TYPE_OFFSET);
    result->scenario_state_bound = 1;

    say(line, "global_scenario_index = 0x%08x", scenarioDatum);
    say(line, "global_scenario       = guest 0x%08x", scenarioBase);
    say(line, "scenario type         = %u%s",
        result->scenario_type,
        result->scenario_type == 2 ? " (main menu)" : "");

    /*
     * struct scenario ends with:
     *   struct tag_block structure_bsp_references; // offset 0x5A4
     * guest tag_block = { int32 count; uint32 address; uint32 definition; }
     */
    const uint8_t *bspBlock = scenario + HALO_SCENARIO_STRUCTURE_BSP_BLOCK_OFFSET;
    const uint32_t bspCount = read_u32le(bspBlock + 0x00);
    const uint32_t bspArrayVA = read_u32le(bspBlock + 0x04);

    result->bsp_reference_count = bspCount;
    result->bsp_reference_array_va = bspArrayVA;

    say(line, "structure BSP refs     = %u @ guest 0x%08x", bspCount, bspArrayVA);

    if (!bspCount || bspCount > 64 ||
        !guest_pointer_sane(bspArrayVA, HALO_SCENARIO_BSP_REFERENCE_SIZE))
    {
        line("ENGINE BLOCKED: ui scenario has no safely resolvable structure BSP reference.");
        return 0;
    }

    /*
     * recovered struct scenario_structure_bsp_reference (0x20 bytes):
     *  +00 file_offset
     *  +04 file_size
     *  +08 base_address
     *  +0C unused
     *  +10 tag_reference.group
     *  +14 tag_reference.name
     *  +18 tag_reference.name_length
     *  +1C tag_reference.index
     */
    uint8_t *reference = halo_guest_ptr(bspArrayVA, HALO_SCENARIO_BSP_REFERENCE_SIZE);
    const uint32_t fileOffset = read_u32le(reference + 0x00);
    const uint32_t fileSize = read_u32le(reference + 0x04);
    const uint32_t loadVA = read_u32le(reference + 0x08);
    const uint32_t refGroup = read_u32le(reference + 0x10);
    const uint32_t refNameVA = read_u32le(reference + 0x14);
    const uint32_t bspTagIndex = read_u32le(reference + 0x1C);

    result->bsp_file_offset = fileOffset;
    result->bsp_file_size = fileSize;
    result->bsp_load_va = loadVA;
    result->bsp_tag_index = bspTagIndex;

    const char *bspName = refNameVA ? halo_guest_ptr(refNameVA, 1) : NULL;

    line("");
    line("scenario_switch_structure_bsp(0):");
    say(line, "  file offset    = 0x%08x", fileOffset);
    say(line, "  file size      = 0x%08x", fileSize);
    say(line, "  load VA        = 0x%08x", loadVA);
    say(line, "  tag datum      = 0x%08x", bspTagIndex);
    say(line, "  tag group      = 0x%08x", refGroup);
    say(line, "  tag name       = %s", bspName ?: "<null>");

    const uint64_t fileEnd = (uint64_t)fileOffset + fileSize;
    if (!fileSize ||
        fileEnd > halo_ios_cache_selected_file_length() ||
        !loadVA)
    {
        line("ENGINE BLOCKED: structure BSP file range/base address is invalid.");
        return 0;
    }

    if (!halo_ios_cache_copy_selected_range_to_guest(fileOffset, fileSize, loadVA))
    {
        line("ENGINE BLOCKED: failed to copy the ui structure BSP payload into guest memory.");
        return 0;
    }
    result->bsp_loaded = 1;

    /*
     * recovered cache_file_structure_bsp_header (0x18):
     *  +00 base_address
     *  +04 vertex_buffer_count
     *  +08 vertex_buffers
     *  +0C index_buffer_count
     *  +10 index_buffers
     *  +14 signature ('sbsp')
     */
    uint8_t *bspHeader = halo_guest_ptr(loadVA, 0x18);
    if (!bspHeader)
    {
        line("ENGINE BLOCKED: loaded BSP header cannot be translated.");
        return 0;
    }

    const uint32_t bspDefinitionVA = read_u32le(bspHeader + 0x00);
    const uint32_t vertexCount = read_u32le(bspHeader + 0x04);
    const uint32_t vertexBuffersVA = read_u32le(bspHeader + 0x08);
    const uint32_t indexCount = read_u32le(bspHeader + 0x0C);
    const uint32_t indexBuffersVA = read_u32le(bspHeader + 0x10);
    const uint32_t bspSignature = read_u32le(bspHeader + 0x14);

    result->bsp_definition_va = bspDefinitionVA;

    line("");
    line("structure BSP cache header:");
    say(line, "  definition VA  = 0x%08x", bspDefinitionVA);
    say(line, "  vertex buffers = %u @ 0x%08x", vertexCount, vertexBuffersVA);
    say(line, "  index buffers  = %u @ 0x%08x", indexCount, indexBuffersVA);
    say(line, "  signature      = 0x%08x", bspSignature);

    if (bspSignature != HALO_STRUCTURE_BSP_GROUP ||
        !guest_pointer_sane(bspDefinitionVA, 4))
    {
        line("ENGINE BLOCKED: structure BSP header/signature is invalid.");
        return 0;
    }
    result->bsp_header_valid = 1;

    /*
     * scenario_structure_bsp_load() binds the sbsp tag instance's base_address
     * to header->base_address after loading. Do the same in the guest tag table.
     */
    const uint32_t bspAbsolute = bspTagIndex & 0xFFFFu;
    if (bspAbsolute >= tagCount ||
        !guest_pointer_sane(tagInstancesVA + bspAbsolute * HALO_TAG_INSTANCE_SIZE,
                            HALO_TAG_INSTANCE_SIZE))
    {
        line("ENGINE BLOCKED: BSP tag datum does not resolve in the tag table.");
        return 0;
    }

    uint8_t *bspInstance =
        halo_guest_ptr(tagInstancesVA + bspAbsolute * HALO_TAG_INSTANCE_SIZE,
                       HALO_TAG_INSTANCE_SIZE);
    const uint32_t instanceGroup = read_u32le(bspInstance + 0x00);
    if (instanceGroup != HALO_STRUCTURE_BSP_GROUP)
    {
        say(line, "ENGINE BLOCKED: BSP tag instance group is 0x%08x, expected 0x%08x",
            instanceGroup, HALO_STRUCTURE_BSP_GROUP);
        return 0;
    }

    write_u32le(bspInstance + 0x14, bspDefinitionVA);
    result->bsp_tag_instance_bound = 1;
    say(line, "PASS bound sbsp tag instance base_address -> 0x%08x", bspDefinitionVA);

    /*
     * scenario_load() next resolves:
     *   tag_loaded(GAME_GLOBALS_TAG, "globals\\globals")
     *   game_globals_definition_get(...)
     */
    uint32_t globalsTag = 0;
    uint32_t globalsBase = 0;
    if (!halo_ios_cache_find_tag(HALO_GAME_GLOBALS_GROUP,
                                 "globals\\globals",
                                 &globalsTag,
                                 &globalsBase))
    {
        line("ENGINE BLOCKED: globals\\globals ('matg') is not present in ui.map.");
        return 0;
    }

    result->game_globals_tag_index = globalsTag;
    result->game_globals_base_va = globalsBase;
    result->game_globals_resolved = globalsBase != 0;

    line("");
    line("scenario_load() globals binding:");
    say(line, "  global_game_globals tag  = 0x%08x", globalsTag);
    say(line, "  global_game_globals base = guest 0x%08x", globalsBase);

    if (!globalsBase || !guest_pointer_sane(globalsBase, 4))
    {
        line("ENGINE BLOCKED: globals\\globals has no valid base address.");
        return 0;
    }

    result->source_scenario_load_complete = 1;

    line("");
    line("SOURCE scenario_load(\"levels\\ui\\ui\") DATA PATH: COMPLETE");
    line("  PASS scenario tag state");
    line("  PASS first structure BSP payload");
    line("  PASS sbsp tag-instance binding");
    line("  PASS globals\\globals binding");
    line("");
    line("ENGINE ENTRY REACHED: the same scenario/BSP/global state required by");
    line("game_load() is now resident at original guest addresses.");
    line("");
    line("NEXT HARD BOUNDARY: game_initialize_for_new_map() fans into the real");
    line("rasterizer, game-state allocator, input, audio, objects, AI, scripts,");
    line("director/observer and render systems. Those recovered modules are not");
    line("yet executable under the iOS LP64 host ABI; invoking them as native");
    line("functions would corrupt their 32-bit pointer layouts.");
    line("");
    line("M2.4 RESULT: ENGINE DATA BOOT COMPLETE; EXECUTION/RUNTIME BRIDGE REQUIRED.");

    return 1;
}
