#ifndef HALO_SCANCODES_H
#define HALO_SCANCODES_H

/*
 * Keyboard key names, as plain C so tools/tests/test_ios_scancodes.c can check them. The game's key bindings (port/linux/src/xinput_sdl.c)
 * ask the host for a key's name and for a name's key (SDL_GetScancodeName and SDL_GetScancodeFromName, which the guest forwards as
 * host_sdl_scancode_name and host_sdl_scancode_from_name). The iOS host has no SDL, so this holds the table: the numbers are SDL3's
 * (the USB keyboard usage numbers) and the names are the ones SDL3 gives them. A number without a name gives "", a name that is not one
 * gives 0 (SDL_SCANCODE_UNKNOWN), and names are matched without regard to case, as SDL does.
 */

#include <stddef.h>

typedef struct { unsigned short code; const char *name; } HscKey;

static const HscKey hsc_keys[] = {
    {4,"A"},{5,"B"},{6,"C"},{7,"D"},{8,"E"},{9,"F"},{10,"G"},{11,"H"},{12,"I"},{13,"J"},{14,"K"},{15,"L"},{16,"M"},
    {17,"N"},{18,"O"},{19,"P"},{20,"Q"},{21,"R"},{22,"S"},{23,"T"},{24,"U"},{25,"V"},{26,"W"},{27,"X"},{28,"Y"},{29,"Z"},
    {30,"1"},{31,"2"},{32,"3"},{33,"4"},{34,"5"},{35,"6"},{36,"7"},{37,"8"},{38,"9"},{39,"0"},
    {40,"Return"},{41,"Escape"},{42,"Backspace"},{43,"Tab"},{44,"Space"},{45,"-"},{46,"="},{47,"["},{48,"]"},{49,"\\"},{50,"#"},
    {51,";"},{52,"'"},{53,"`"},{54,","},{55,"."},{56,"/"},{57,"CapsLock"},
    {58,"F1"},{59,"F2"},{60,"F3"},{61,"F4"},{62,"F5"},{63,"F6"},{64,"F7"},{65,"F8"},{66,"F9"},{67,"F10"},{68,"F11"},{69,"F12"},
    {70,"PrintScreen"},{71,"ScrollLock"},{72,"Pause"},{73,"Insert"},{74,"Home"},{75,"PageUp"},{76,"Delete"},{77,"End"},{78,"PageDown"},
    {79,"Right"},{80,"Left"},{81,"Down"},{82,"Up"},{83,"Numlock"},
    {84,"Keypad /"},{85,"Keypad *"},{86,"Keypad -"},{87,"Keypad +"},{88,"Keypad Enter"},
    {89,"Keypad 1"},{90,"Keypad 2"},{91,"Keypad 3"},{92,"Keypad 4"},{93,"Keypad 5"},{94,"Keypad 6"},{95,"Keypad 7"},{96,"Keypad 8"},{97,"Keypad 9"},
    {98,"Keypad 0"},{99,"Keypad ."},{100,"NonUSBackslash"},{101,"Application"},{102,"Power"},{103,"Keypad ="},
    {104,"F13"},{105,"F14"},{106,"F15"},{107,"F16"},{108,"F17"},{109,"F18"},{110,"F19"},{111,"F20"},{112,"F21"},{113,"F22"},{114,"F23"},{115,"F24"},
    {224,"Left Ctrl"},{225,"Left Shift"},{226,"Left Alt"},{227,"Left GUI"},{228,"Right Ctrl"},{229,"Right Shift"},{230,"Right Alt"},{231,"Right GUI"}
};
#define HSC_COUNT ((int)(sizeof(hsc_keys) / sizeof(hsc_keys[0])))

/* the key's name, or "" for a number that is not a key here */
static inline const char *hsc_name(int scancode)
{
    for (int i = 0; i < HSC_COUNT; i++)
        if (hsc_keys[i].code == scancode)
            return hsc_keys[i].name;
    return "";
}

static inline int hsc_equal_nocase(const char *a, const char *b)
{
    for (;; a++, b++)
    {
        int x = (unsigned char)*a, y = (unsigned char)*b;
        if (x >= 'A' && x <= 'Z') x += 32;
        if (y >= 'A' && y <= 'Z') y += 32;
        if (x != y)
            return 0;
        if (!x)
            return 1;
    }
}

/* the key with this name (any case), or 0 */
static inline int hsc_from_name(const char *name)
{
    if (!name || !*name)
        return 0;
    for (int i = 0; i < HSC_COUNT; i++)
        if (hsc_equal_nocase(name, hsc_keys[i].name))
            return hsc_keys[i].code;
    return 0;
}

#endif
