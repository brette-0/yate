// NES master palette data.
//
// The 2C02 PPU can produce 64 colours (indices $00-$3F). A 2bpp NES tile
// selects 4 of these per palette. These RGB values are the classic/canonical
// NES palette used by most editors and emulators -- they are for PREVIEW only
// and are never written to the CHR data.
module yate::nes;

import raylib6::rl;

// 56 colours, laid out as 4 rows of 14 (matching $x0..$xD per row). Hardware has
// 64 entries, but the two rightmost columns ($xE/$xF, eight cells) are all the
// same pure black -- since this table is preview-only and never exported, those
// duplicates are dropped rather than stored.
const RLColor[56] PALETTE = {
    // $00-$0D
    { 124, 124, 124, 255 }, {   0,   0, 252, 255 }, {   0,   0, 188, 255 }, {  68,  40, 188, 255 },
    { 148,   0, 132, 255 }, { 168,   0,  32, 255 }, { 168,  16,   0, 255 }, { 136,  20,   0, 255 },
    {  80,  48,   0, 255 }, {   0, 120,   0, 255 }, {   0, 104,   0, 255 }, {   0,  88,   0, 255 },
    {   0,  64,  88, 255 }, {   0,   0,   0, 255 },
    // $10-$1D
    { 188, 188, 188, 255 }, {   0, 120, 248, 255 }, {   0,  88, 248, 255 }, { 104,  68, 252, 255 },
    { 216,   0, 204, 255 }, { 228,   0,  88, 255 }, { 248,  56,   0, 255 }, { 228,  92,  16, 255 },
    { 172, 124,   0, 255 }, {   0, 184,   0, 255 }, {   0, 168,   0, 255 }, {   0, 168,  68, 255 },
    {   0, 136, 136, 255 }, {   0,   0,   0, 255 },
    // $20-$2D
    { 248, 248, 248, 255 }, {  60, 188, 252, 255 }, { 104, 136, 252, 255 }, { 152, 120, 248, 255 },
    { 248, 120, 248, 255 }, { 248,  88, 152, 255 }, { 248, 120,  88, 255 }, { 252, 160,  68, 255 },
    { 248, 184,   0, 255 }, { 184, 248,  24, 255 }, {  88, 216,  84, 255 }, {  88, 248, 152, 255 },
    {   0, 232, 216, 255 }, { 120, 120, 120, 255 },
    // $30-$3D
    { 252, 252, 252, 255 }, { 164, 228, 252, 255 }, { 184, 184, 248, 255 }, { 216, 184, 248, 255 },
    { 248, 184, 248, 255 }, { 248, 164, 192, 255 }, { 240, 208, 176, 255 }, { 252, 224, 168, 255 },
    { 248, 216, 120, 255 }, { 216, 248, 120, 255 }, { 184, 248, 184, 255 }, { 184, 248, 216, 255 },
    {   0, 252, 252, 255 }, { 216, 216, 216, 255 },
};
