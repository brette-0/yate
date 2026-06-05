// Palette editor region (bottom slice of the window), split into two halves:
//
//   bottom-LEFT  : the 56 NES master colours (the possible colours to pick).
//   bottom-RIGHT : NUM_PAL editable 2bpp palettes, each a 2x2 of colours.
//
// Interaction: clicking a palette colour selects it (animated green ants mark the
// chosen palette, a blue dotted box marks the chosen colour); clicking any colour
// in the left selector writes it into that highlighted slot.
module yate::palette;

import raylib6::rl;
import std::math; // for Rect
import yate::ui;
import yate::nes;

// Number of editable 2bpp palettes shown bottom-right, each 4 colours.
const int NUM_PAL = 4;

// The active palettes: NUM_PAL * 4 indices into the NES master palette, laid out
// as [p*4 + c]. Indices are into our trimmed 56-colour table (14 per row), so a
// colour at hardware $rc lives at row*14 + col. Defaults: reds, greens, blues,
// and a black->white grey ramp; slot 0 of each is the shared black backdrop ($0D).
int[16] active = {
    13,  6, 20, 34, // palette 0: reds
    13, 10, 24, 38, // palette 1: greens
    13,  2, 16, 30, // palette 2: blues
    13,  0, 14, 42, // palette 3: black, grey, light grey, white
};

// Current selection: which palette, and which colour slot within it.
int sel_pal = 0;
int sel_col = 0;

// Index into `active` for colour `col` of palette `pal`. Colour 0 is the NES
// shared backdrop: every palette's slot 0 aliases palette 0's, so reads show the
// same colour everywhere and a write to any slot 0 updates them all at once.
fn int slot(int pal, int col) => col == 0 ? 0 : pal * 4 + col;

const RLColor BG      = { 28,  30,  34,  255 };
const RLColor BORDER  = { 60,  63,  70,  255 };
const RLColor GRID    = { 20,  21,  24,  255 };
const RLColor SEL_PAL = { 80,  220, 120, 255 }; // selected-palette marching ants
const RLColor SEL_COL = { 90,  170, 255, 255 }; // selected-colour dotted box

// Draw the whole palette editor inside `r`.
fn void draw(Rect r) {
    rl::draw_rectangle_rec(r, BG);
    rl::draw_rectangle_lines_ex(r, ui::px(1), BORDER);

    Rect inner = ui::inset(r, ui::px(8));
    float gap  = ui::px(8);

    // Split into two equal halves with a gap between them.
    ui::Split halves = ui::split_left(inner, (inner.width - gap) * 0.5f);
    Rect left  = halves.a;
    Rect right = { .x = halves.b.x + gap, .y = halves.b.y, .width = halves.b.width - gap, .height = halves.b.height };

    draw_nes_grid(left);
    draw_active_palettes(right);
}

// 56 NES colours as a 14x4 grid filling `area` edge to edge. Clicking a cell
// writes that colour into the currently selected palette slot.
fn void draw_nes_grid(Rect area) {
    float cell_w = area.width  / 14.0f;
    float cell_h = area.height / 4.0f;

    RLVector2 mouse = rl::get_mouse_position();
    bool click = rl::is_mouse_button_released(rl::RLMouseButton.LEFT);

    for (int idx = 0; idx < 56; idx++) {
        int col = idx % 14;
        int row = idx / 14;
        Rect c = { .x = area.x + (float)col * cell_w, .y = area.y + (float)row * cell_h, .width = cell_w, .height = cell_h };
        rl::draw_rectangle_rec(c, nes::PALETTE[idx]);
        rl::draw_rectangle_lines_ex(c, ui::px(1), GRID);
        if (click && rl::check_collision_point_rec(mouse, c)) active[slot(sel_pal, sel_col)] = idx;
    }
}

// NUM_PAL editable palettes in a row, each a 2x2 of square colour cells, packed
// flush together. Sized to fit and centred in `area`.
//
//   P0C0 P0C1 P1C0 P1C1 ...
//   P0C2 P0C3 P1C2 P1C3 ...
fn void draw_active_palettes(Rect area) {
    $assert(NUM_PAL * 4 == active.len); // 4 colours per palette

    // Square cells: two rows tall, NUM_PAL*2 columns wide -- take whichever axis
    // is the tighter fit so the cells stay square.
    float cell_h = area.height * 0.5f;
    float cell_w = area.width / (float)(NUM_PAL * 2);
    float cell   = cell_h < cell_w ? cell_h : cell_w;

    float block_w = (float)(NUM_PAL * 2) * cell;
    float block_h = 2.0f * cell;
    float ox = area.x + (area.width  - block_w) * 0.5f;
    float oy = area.y + (area.height - block_h) * 0.5f;

    float stride = 2.0f * cell; // x distance from one palette to the next

    RLVector2 mouse = rl::get_mouse_position();
    bool click = rl::is_mouse_button_released(rl::RLMouseButton.LEFT);

    for (int p = 0; p < NUM_PAL; p++) {
        float px0 = ox + (float)p * stride;

        for (int c = 0; c < 4; c++) {
            float x = px0 + (float)(c % 2) * cell;
            float y = oy  + (float)(c / 2) * cell;
            Rect q = { .x = x, .y = y, .width = cell, .height = cell };
            rl::draw_rectangle_rec(q, nes::PALETTE[active[slot(p, c)]]);
            rl::draw_rectangle_lines_ex(q, ui::px(1), GRID);
            if (click && rl::check_collision_point_rec(mouse, q)) { sel_pal = p; sel_col = c; }
        }
    }

    // Selection markers, drawn on top of the cells. Both sets of ants march at
    // the same animated offset so the chosen palette and colour move in step.
    float ants = (float)rl::get_time() * ui::px(24);
    float spx  = ox + (float)sel_pal * stride;

    Rect block = { .x = spx, .y = oy, .width = 2.0f * cell, .height = block_h };
    ui::dots(ui::inset(block, -ui::px(1)), SEL_PAL, ants);

    Rect slot = { .x = spx + (float)(sel_col % 2) * cell, .y = oy + (float)(sel_col / 2) * cell, .width = cell, .height = cell };
    ui::dots(ui::inset(slot, ui::px(2)), SEL_COL, ants);
}

// Colour of palette slot `pix` (0..3) of the currently selected palette, used by
// the tile preview to render graphics through the active palette.
fn RLColor tile_color(int pix) {
    return nes::PALETTE[active[slot(sel_pal, pix)]];
}

// The pen: the 2bpp colour index (0..3) drawing writes -- the selected slot.
fn int selected_color() => sel_col;
