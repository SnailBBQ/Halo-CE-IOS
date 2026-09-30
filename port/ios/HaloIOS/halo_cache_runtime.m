#import "halo_cache_runtime.h"

#import <Foundation/Foundation.h>

#include "halo_guest_runtime.h"

#include <stdint.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>
#include <strings.h>
#include <zlib.h>

#define HALO_CACHE_HEADER_SIZE        UINT32_C(0x800)
#define HALO_TAG_CACHE_BASE_VA        UINT32_C(0x803A6000)
#define HALO_TAG_CACHE_CAPACITY       UINT32_C(0x01600000)
#define HALO_TAG_INSTANCE_SIZE        UINT32_C(0x20)
#define HALO_TAG_HEADER_SIZE          UINT32_C(0x24)

static NSData *g_selected_cache_image;
static uint32_t g_tag_instances_va;
static uint32_t g_tag_count;
static uint32_t g_scenario_tag_index;
static uint32_t g_scenario_base_va;
static uint32_t g_selected_file_length;

static void say(void (^line)(const char *), const char *fmt, ...)
{
    char buffer[1024];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(buffer, sizeof(buffer), fmt, ap);
    va_end(ap);
    line(buffer);
}

static uint32_t read_u32le(const uint8_t *p)
{
    return ((uint32_t)p[0]) |
           ((uint32_t)p[1] << 8) |
           ((uint32_t)p[2] << 16) |
           ((uint32_t)p[3] << 24);
}

static int signature_matches(const uint8_t *p,
                             const char *forward,
                             const char *reverse)
{
    return memcmp(p, forward, 4) == 0 || memcmp(p, reverse, 4) == 0;
}

static NSString *fixed_c_string(const uint8_t *p, NSUInteger length)
{
    NSUInteger n = 0;
    while (n < length && p[n] != 0)
        ++n;
    NSData *data = [NSData dataWithBytes:p length:n];
    NSString *s = [[NSString alloc] initWithData:data encoding:NSASCIIStringEncoding];
    return s ?: @"";
}

static NSString *maps_directory(void)
{
    NSString *home = NSHomeDirectory() ?: @"";
    NSString *halo = [home stringByAppendingPathComponent:@"Documents/Halo"];
    NSString *maps = [halo stringByAppendingPathComponent:@"maps"];

    NSError *error = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:maps
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:&error])
    {
        return maps;
    }

    NSString *marker = [halo stringByAppendingPathComponent:@"PUT_HALO_MAPS_HERE.txt"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:marker])
    {
        NSString *instructions =
            @"Halo iOS content folder\n\n"
             "Copy your Halo CE Universal .map files into the maps folder next to this file.\n"
             "Expected path: Documents/Halo/maps\n";
        [instructions writeToFile:marker
                       atomically:YES
                         encoding:NSUTF8StringEncoding
                            error:nil];
    }

    return maps;
}

static NSArray<NSString *> *map_files_sorted(NSString *mapsPath)
{
    NSError *error = nil;
    NSArray<NSString *> *items =
        [[NSFileManager defaultManager] contentsOfDirectoryAtPath:mapsPath error:&error];
    if (!items)
        return @[];

    NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(NSString *item, NSDictionary *bindings) {
        (void)bindings;
        return [[item.pathExtension lowercaseString] isEqualToString:@"map"];
    }];

    return [[items filteredArrayUsingPredicate:predicate]
            sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

typedef struct halo_parsed_map_header
{
    uint32_t version;
    uint32_t file_length;
    uint32_t tag_data_offset;
    uint32_t tag_data_size;
    uint32_t checksum;
    NSString *name;
    NSString *build;
} halo_parsed_map_header;

static int parse_cache_header(NSData *headerData,
                              unsigned long long physicalFileSize,
                              halo_parsed_map_header *out)
{
    if (headerData.length < HALO_CACHE_HEADER_SIZE || physicalFileSize < HALO_CACHE_HEADER_SIZE)
        return 0;

    const uint8_t *b = headerData.bytes;

    if (!signature_matches(b + 0x000, "head", "daeh"))
        return 0;
    if (!signature_matches(b + 0x7FC, "foot", "toof"))
        return 0;

    uint32_t version = read_u32le(b + 0x004);
    uint32_t file_length = read_u32le(b + 0x008);
    uint32_t tag_data_offset = read_u32le(b + 0x010);
    uint32_t tag_data_size = read_u32le(b + 0x014);

    /*
     * Recovered cache_files.c validates the declared cache length against the
     * Xbox cache maximum, not against the physical source-file byte count.
     * cache_files_decompress_windows.c copies the 0x800-byte header verbatim and
     * inflates the body with zlib. The .map files on the content volume can
     * therefore be smaller than header.file_length.
     */
    if (version != 5)
        return 0;
    if (file_length < HALO_CACHE_HEADER_SIZE || file_length > UINT32_C(0x11600000))
        return 0;
    if (tag_data_size == 0 || tag_data_size > HALO_TAG_CACHE_CAPACITY)
        return 0;
    if ((uint64_t)tag_data_offset + tag_data_size > file_length)
        return 0;

    out->version = version;
    out->file_length = file_length;
    out->tag_data_offset = tag_data_offset;
    out->tag_data_size = tag_data_size;
    out->name = fixed_c_string(b + 0x020, 0x20);
    out->build = fixed_c_string(b + 0x040, 0x20);
    out->checksum = read_u32le(b + 0x064);
    return 1;
}

static NSData *load_cache_image(NSString *path,
                                halo_parsed_map_header header,
                                void (^line)(const char *))
{
    NSError *error = nil;
    NSData *source = [NSData dataWithContentsOfFile:path
                                            options:NSDataReadingMappedIfSafe
                                              error:&error];
    if (!source)
    {
        say(line, "BOOT BLOCKED: unable to read %s (%s)",
            path.lastPathComponent.UTF8String,
            error.localizedDescription.UTF8String ?: "unknown");
        return nil;
    }

    if (source.length < HALO_CACHE_HEADER_SIZE)
        return nil;

    /*
     * A fully expanded cache can be consumed directly. Otherwise mirror the
     * recovered Xbox/Windows cache copier: preserve the header and inflate the
     * body beginning at byte 0x800.
     */
    if (source.length == header.file_length)
    {
        say(line, "CACHE IMAGE: %s is already expanded (%llu bytes)",
            path.lastPathComponent.UTF8String,
            (unsigned long long)source.length);
        return source;
    }

    if (source.length > header.file_length)
    {
        say(line, "CACHE IMAGE: source is larger than declared image; using first 0x%08x bytes",
            header.file_length);
        return [source subdataWithRange:NSMakeRange(0, header.file_length)];
    }

    uint8_t *expanded = malloc(header.file_length);
    if (!expanded)
    {
        line("BOOT BLOCKED: unable to allocate expanded cache image.");
        return nil;
    }

    memcpy(expanded, source.bytes, HALO_CACHE_HEADER_SIZE);

    z_stream stream;
    memset(&stream, 0, sizeof(stream));
    int zr = inflateInit(&stream);
    if (zr != Z_OK)
    {
        free(expanded);
        say(line, "BOOT BLOCKED: inflateInit failed (%d)", zr);
        return nil;
    }

    stream.next_in = (Bytef *)source.bytes + HALO_CACHE_HEADER_SIZE;
    stream.avail_in = (uInt)(source.length - HALO_CACHE_HEADER_SIZE);
    stream.next_out = expanded + HALO_CACHE_HEADER_SIZE;
    stream.avail_out = header.file_length - HALO_CACHE_HEADER_SIZE;

    zr = inflate(&stream, Z_FINISH);
    uLong produced = stream.total_out;
    inflateEnd(&stream);

    if (zr != Z_STREAM_END ||
        produced != (uLong)(header.file_length - HALO_CACHE_HEADER_SIZE))
    {
        say(line,
            "BOOT BLOCKED: zlib cache expansion failed result=%d produced=0x%lx expected=0x%08x",
            zr,
            (unsigned long)produced,
            header.file_length - HALO_CACHE_HEADER_SIZE);
        free(expanded);
        return nil;
    }

    say(line, "CACHE EXPANDED: %s %llu -> %u bytes",
        path.lastPathComponent.UTF8String,
        (unsigned long long)source.length,
        header.file_length);

    return [NSData dataWithBytesNoCopy:expanded
                                length:header.file_length
                          freeWhenDone:YES];
}

static int read_exact(NSFileHandle *handle, uint64_t offset, NSUInteger count, NSData **outData)
{
    @try
    {
        [handle seekToFileOffset:offset];
        NSData *data = [handle readDataOfLength:count];
        if (data.length != count)
            return 0;
        *outData = data;
        return 1;
    }
    @catch (NSException *exception)
    {
        (void)exception;
        return 0;
    }
}

static int guest_range_is_loaded(uint32_t va, uint32_t size, uint32_t loadedSize)
{
    uint64_t start = va;
    uint64_t end = start + size;
    uint64_t loadedStart = HALO_TAG_CACHE_BASE_VA;
    uint64_t loadedEnd = loadedStart + loadedSize;
    return end >= start && start >= loadedStart && end <= loadedEnd;
}

static NSString *fourcc_string(uint32_t value)
{
    char s[5];
    s[0] = (char)(value & 0xFF);
    s[1] = (char)((value >> 8) & 0xFF);
    s[2] = (char)((value >> 16) & 0xFF);
    s[3] = (char)((value >> 24) & 0xFF);
    s[4] = 0;

    for (int i = 0; i < 4; ++i)
    {
        if ((unsigned char)s[i] < 0x20 || (unsigned char)s[i] > 0x7E)
            s[i] = '?';
    }
    return [NSString stringWithUTF8String:s] ?: @"????";
}

int halo_ios_cache_bootstrap(void (^line)(const char *text),
                             halo_ios_cache_boot_result *result)
{
    memset(result, 0, sizeof(*result));
    g_selected_cache_image = nil;
    g_tag_instances_va = 0;
    g_tag_count = 0;
    g_scenario_tag_index = 0;
    g_scenario_base_va = 0;
    g_selected_file_length = 0;

    NSString *mapsPath = maps_directory();
    NSArray<NSString *> *maps = map_files_sorted(mapsPath);
    result->discovered_maps = (uint32_t)maps.count;

    say(line, "MAP ROOT: %s", mapsPath.UTF8String);
    say(line, "DISCOVERED: %u .map files", result->discovered_maps);

    if (maps.count == 0)
    {
        line("BOOT BLOCKED: no .map files are available.");
        return 0;
    }

    NSString *selectedPath = nil;
    halo_parsed_map_header selectedHeader = {0};

    line("");
    line("CACHE INDEX:");

    for (NSString *filename in maps)
    {
        NSString *path = [mapsPath stringByAppendingPathComponent:filename];
        NSDictionary *attrs =
            [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
        unsigned long long actualSize = [attrs fileSize];

        NSFileHandle *handle = [NSFileHandle fileHandleForReadingAtPath:path];
        if (!handle)
        {
            say(line, "  SKIP %-28s open failed", filename.UTF8String);
            continue;
        }

        NSData *headerData = nil;
        halo_parsed_map_header header = {0};
        int valid =
            read_exact(handle, 0, HALO_CACHE_HEADER_SIZE, &headerData) &&
            parse_cache_header(headerData, actualSize, &header);
        [handle closeFile];

        if (!valid)
        {
            say(line, "  SKIP %-28s invalid cache header", filename.UTF8String);
            continue;
        }

        result->valid_maps++;
        const char *storage = (actualSize == header.file_length) ? "expanded" : "zlib";
        say(line, "  MAP  %-24s name=%-16s build=%-14s %s %llu/%u",
            filename.UTF8String,
            header.name.UTF8String,
            header.build.UTF8String,
            storage,
            actualSize,
            header.file_length);

        if ([[filename lowercaseString] isEqualToString:@"ui.map"])
        {
            selectedPath = path;
            selectedHeader = header;
        }
    }

    say(line, "VALID CACHE FILES: %u/%u", result->valid_maps, result->discovered_maps);

    if (!selectedPath)
    {
        line("");
        line("BOOT BLOCKED: ui.map was not found as a valid cache file.");
        line("The real menu/startup path needs a usable ui.map before engine boot can continue.");
        return 0;
    }

    result->selected_map_found = 1;
    result->header_valid = 1;

    line("");
    line("SELECTED STARTUP CACHE: ui.map");
    say(line, "  scenario name : %s", selectedHeader.name.UTF8String);
    say(line, "  build         : %s", selectedHeader.build.UTF8String);
    say(line, "  file length   : 0x%08x", selectedHeader.file_length);
    say(line, "  tag offset    : 0x%08x", selectedHeader.tag_data_offset);
    say(line, "  tag size      : 0x%08x", selectedHeader.tag_data_size);
    say(line, "  checksum      : 0x%08x", selectedHeader.checksum);

    /*
     * source/cache/cache_files.c::scenario_tags_load() places the complete tag
     * data block at physical_memory_get_tag_cache_base_address(), whose Xbox
     * address is 0x803A6000 and whose capacity is 0x01600000 bytes.
     */
    if (!halo_guest_commit(HALO_TAG_CACHE_BASE_VA, HALO_TAG_CACHE_CAPACITY))
    {
        line("BOOT BLOCKED: could not commit the original Xbox tag-cache region.");
        return 0;
    }

    NSData *cacheImage = load_cache_image(selectedPath, selectedHeader, line);
    if (!cacheImage)
        return 0;

    g_selected_cache_image = cacheImage;
    g_selected_file_length = selectedHeader.file_length;
    result->selected_file_length = selectedHeader.file_length;

    if ((uint64_t)selectedHeader.tag_data_offset + selectedHeader.tag_data_size > cacheImage.length)
    {
        line("BOOT BLOCKED: expanded ui.map does not contain the declared tag-data range.");
        return 0;
    }

    NSData *tagData =
        [cacheImage subdataWithRange:NSMakeRange(selectedHeader.tag_data_offset,
                                                 selectedHeader.tag_data_size)];

    void *tagCache = halo_guest_ptr(HALO_TAG_CACHE_BASE_VA,
                                    selectedHeader.tag_data_size);
    if (!tagCache)
    {
        line("BOOT BLOCKED: tag-cache guest pointer translation failed.");
        return 0;
    }

    memset(tagCache, 0xCD, HALO_TAG_CACHE_CAPACITY);
    memcpy(tagCache, tagData.bytes, selectedHeader.tag_data_size);
    result->tag_data_loaded = 1;
    result->selected_tag_data_size = selectedHeader.tag_data_size;

    say(line, "LOADED: 0x%08x bytes of ui.map tag data -> guest 0x%08x (host %p)",
        selectedHeader.tag_data_size, HALO_TAG_CACHE_BASE_VA, tagCache);

    if (selectedHeader.tag_data_size < HALO_TAG_HEADER_SIZE)
    {
        line("BOOT BLOCKED: tag-data payload is too small for a tag header.");
        return 0;
    }

    const uint8_t *tagHeader = tagCache;
    uint32_t tagInstancesVA = read_u32le(tagHeader + 0x00);
    uint32_t scenarioTagIndex = read_u32le(tagHeader + 0x04);
    uint32_t tagChecksum = read_u32le(tagHeader + 0x08);
    uint32_t tagCount = read_u32le(tagHeader + 0x0C);

    if (!signature_matches(tagHeader + 0x20, "tags", "sgat"))
    {
        say(line, "BOOT BLOCKED: tag header signature was not 'tags' (raw=0x%08x)",
            read_u32le(tagHeader + 0x20));
        return 0;
    }

    if (tagCount == 0 || tagCount > 65535)
    {
        say(line, "BOOT BLOCKED: implausible tag count %u", tagCount);
        return 0;
    }

    result->tag_header_valid = 1;
    result->selected_tag_count = tagCount;
    result->selected_scenario_tag_index = scenarioTagIndex;
    result->selected_tag_instances_va = tagInstancesVA;
    g_tag_instances_va = tagInstancesVA;
    g_tag_count = tagCount;
    g_scenario_tag_index = scenarioTagIndex;

    line("");
    line("REAL TAG CACHE ONLINE:");
    say(line, "  tag_instances VA : 0x%08x", tagInstancesVA);
    say(line, "  scenario index   : 0x%08x", scenarioTagIndex);
    say(line, "  tag checksum     : 0x%08x", tagChecksum);
    say(line, "  tag count        : %u", tagCount);

    uint32_t absoluteIndex = scenarioTagIndex & 0xFFFFu;
    if (absoluteIndex >= tagCount ||
        !guest_range_is_loaded(tagInstancesVA,
                               tagCount * HALO_TAG_INSTANCE_SIZE,
                               selectedHeader.tag_data_size))
    {
        line("BOOT BLOCKED: scenario tag table is not safely resolvable in loaded tag memory.");
        return 0;
    }

    uint8_t *instances = halo_guest_ptr(tagInstancesVA,
                                        tagCount * HALO_TAG_INSTANCE_SIZE);
    if (!instances)
    {
        line("BOOT BLOCKED: tag-instance guest pointer translation failed.");
        return 0;
    }

    uint8_t *scenarioInstance =
        instances + absoluteIndex * HALO_TAG_INSTANCE_SIZE;

    uint32_t groupTag = read_u32le(scenarioInstance + 0x00);
    uint32_t instanceTagIndex = read_u32le(scenarioInstance + 0x0C);
    uint32_t nameVA = read_u32le(scenarioInstance + 0x10);
    uint32_t baseVA = read_u32le(scenarioInstance + 0x14);
    result->selected_scenario_base_va = baseVA;
    g_scenario_base_va = baseVA;

    NSString *scenarioName = @"<unresolved>";
    if (guest_range_is_loaded(nameVA, 1, selectedHeader.tag_data_size))
    {
        const char *name = halo_guest_ptr(nameVA, 1);
        if (name)
        {
            size_t maxLen =
                (HALO_TAG_CACHE_BASE_VA + selectedHeader.tag_data_size) - nameVA;
            if (maxLen > 255)
                maxLen = 255;
            size_t n = strnlen(name, maxLen);
            scenarioName =
                [[NSString alloc] initWithBytes:name
                                        length:n
                                      encoding:NSASCIIStringEncoding] ?: @"<invalid-ascii>";
        }
    }

    result->scenario_instance_resolved = 1;

    line("");
    line("STARTUP SCENARIO RESOLVED FROM REAL ui.map:");
    say(line, "  absolute index : %u", absoluteIndex);
    say(line, "  datum index    : 0x%08x", instanceTagIndex);
    say(line, "  group          : %s (0x%08x)",
        fourcc_string(groupTag).UTF8String, groupTag);
    say(line, "  name VA        : 0x%08x", nameVA);
    say(line, "  base VA        : 0x%08x", baseVA);
    say(line, "  name           : %s", scenarioName.UTF8String);

    line("");
    line("CACHE STAGE COMPLETE: ui.map tag state is resident and retained for engine startup.");

    return 1;
}

int halo_ios_cache_copy_selected_range(uint32_t file_offset,
                                       uint32_t size,
                                       void *destination)
{
    if (!g_selected_cache_image || !destination || size == 0)
        return 0;

    uint64_t end = (uint64_t)file_offset + size;
    if (end > g_selected_cache_image.length)
        return 0;

    memcpy(destination,
           (const uint8_t *)g_selected_cache_image.bytes + file_offset,
           size);
    return 1;
}

int halo_ios_cache_copy_selected_range_to_guest(uint32_t file_offset,
                                                uint32_t size,
                                                uint32_t guest_va)
{
    if (!size || !halo_guest_commit(guest_va, size))
        return 0;

    void *destination = halo_guest_ptr(guest_va, size);
    if (!destination)
        return 0;

    return halo_ios_cache_copy_selected_range(file_offset, size, destination);
}

int halo_ios_cache_find_tag(uint32_t group_tag,
                            const char *name,
                            uint32_t *tag_index,
                            uint32_t *base_va)
{
    if (!g_tag_instances_va || !g_tag_count || !name)
        return 0;

    uint8_t *instances =
        halo_guest_ptr(g_tag_instances_va, g_tag_count * HALO_TAG_INSTANCE_SIZE);
    if (!instances)
        return 0;

    for (uint32_t i = 0; i < g_tag_count; ++i)
    {
        uint8_t *instance = instances + i * HALO_TAG_INSTANCE_SIZE;
        uint32_t group = read_u32le(instance + 0x00);
        uint32_t datum = read_u32le(instance + 0x0C);
        uint32_t name_va = read_u32le(instance + 0x10);
        uint32_t base = read_u32le(instance + 0x14);

        if (group != group_tag || !name_va)
            continue;

        const char *candidate = halo_guest_ptr(name_va, 1);
        if (!candidate)
            continue;

        if (!strcasecmp(candidate, name))
        {
            if (tag_index)
                *tag_index = datum;
            if (base_va)
                *base_va = base;
            return 1;
        }
    }

    return 0;
}

uint32_t halo_ios_cache_tag_instances_va(void)
{
    return g_tag_instances_va;
}

uint32_t halo_ios_cache_tag_count(void)
{
    return g_tag_count;
}

uint32_t halo_ios_cache_scenario_tag_index(void)
{
    return g_scenario_tag_index;
}

uint32_t halo_ios_cache_scenario_base_va(void)
{
    return g_scenario_base_va;
}

uint32_t halo_ios_cache_selected_file_length(void)
{
    return g_selected_file_length;
}
