module yate;

import raylib6::rl;
import yate::layout;
import yate::ui;
import yate::palette;
import yate::toolbar;
import yate::tools;
import yate::tiles;
import yate::dialog;
import std::math; // for Rect

// --- Theme -------------------------------------------------------------------
const RLColor BG_APP = { 16,  17,  19,  255 }; // window background
const RLColor LABEL  = { 150, 155, 165, 255 }; // captions

// Integer window scale. Scaling is locked (the window is not user-resizable):
// 1x is the smallest size -- the reference design size -- and every step up is a
// whole multiple of it, up to the largest that still fits the monitor.
int win_scale = 1;

const ZString[9] SCALE_LABELS = {
    "scale 1x", "scale 2x", "scale 3x", "scale 4x", "scale 5x",
    "scale 6x", "scale 7x", "scale 8x", "scale 9x",
};

// Largest integer scale whose window still fits the current monitor (>= 1),
// capped to the number of labels we have.
fn int max_scale() {
    int   mon = rl::get_current_monitor();
    float mw  = (float)rl::get_monitor_width(mon);
    float mh  = (float)rl::get_monitor_height(mon);

    // If the monitor query failed (e.g. the window straddles two outputs and the
    // current monitor is reported with no size), fall back to the safe minimum.
    if (mw < 1.0f || mh < 1.0f) return 1;

    int k = 1;
    while (k < SCALE_LABELS.len
        && layout::ref_w * (float)(k + 1) <= mw
        && layout::ref_h * (float)(k + 1) <= mh) k++;
    return k;
}

// Resize the window to the current integer scale.
fn void apply_scale() {
    float w = layout::ref_w * (float)win_scale;
    float h = layout::ref_h * (float)win_scale;
    rl::set_window_size((int)(w + 0.5f), (int)(h + 0.5f));
}

// Set the scale, clamped to [1, max_scale], and resize the window to match.
fn void set_scale(int s) {
    int mx = max_scale();
    win_scale = s < 1 ? 1 : (s > mx ? mx : s);
    apply_scale();
}

// Step to the next integer scale, wrapping back to 1x past the largest that fits.
// Any anomaly in the monitor check (mx < 1, or we're already at/above it) resets
// to 1x rather than risk an oversized or garbage window size.
fn void cycle_scale() {
    int mx = max_scale();
    win_scale = (mx < 1 || win_scale >= mx) ? 1 : win_scale + 1;
    apply_scale();
}

// Load yate.png as the window icon (title bar / taskbar). It's converted to the
// RGBA32 format SetWindowIcon expects, and the CPU-side copy is freed once the
// window has taken its own. A missing file just leaves the default icon -- raylib
// logs it and load_image returns an empty image. (Note: GLFW only applies this on
// X11; under Wayland the icon comes from the .desktop file's Icon= entry instead.)
fn void set_app_icon() {
    rl::RLImage icon = rl::load_image("yate.png");
    if (icon.data == null) return;
    rl::image_format(&icon, rl::RLPixelFormat.UNCOMPRESSED_R8G8B8A8);
    rl::set_window_icon(icon);
    rl::unload_image(icon);
}

// A caption sitting just above the top-left corner of `r`.
fn void caption(Rect r, ZString text) {
    int font = (int)ui::px(12);
    rl::draw_text(text, (int)r.x, (int)(r.y - ui::px(15)), font, LABEL);
}

// Show the native open dialog and, if a file is chosen, load it. Loading always
// discards the current scene; an invalid file leaves the scene empty.
fn void open_file() {
    char[4096] path;
    if (dialog::pick_file(&path[0], 4096)) tiles::load((ZString)&path[0]);
}

// Show the native save dialog and, if a path is chosen, create a fresh empty CHR
// file there (512 tiles, 8 KiB) and load it for editing.
fn void new_file() {
    char[4096] path;
    if (dialog::pick_save_file(&path[0], 4096)) tiles::create((ZString)&path[0]);
}

// Save dialog pre-filled with the opened name + "_rle"; on confirm, export the
// scene as RLE (for CHR-RAM games streaming graphics to the PPU). Scene untouched.
fn void compress_file() {
    if (!tiles::loaded()) return;
    char[4096] suggest;
    tiles::suggest_rle_name(&suggest[0], 4096);
    char[4096] path;
    if (dialog::pick_save_file_named((ZString)&suggest[0], &path[0], 4096)) {
        tiles::compress((ZString)&path[0]);
    }
}

// Without Ctrl: R/X/Y transform the selection (rotate / mirror X / mirror Y) and
// G toggles the Edit grid. With Ctrl: C/X copy/cut and V paste the tile selection,
// Z/Y are undo/redo of the last action, +/- step the scale, 0 resets, 1..9 jump.
fn void handle_input() {
    bool ctrl = rl::is_key_down(rl::RLKeyboardKey.LEFT_CONTROL)
             || rl::is_key_down(rl::RLKeyboardKey.RIGHT_CONTROL);

    if (!ctrl) {
        // D/F/C/S switch the active drawing tool; R/X/Y transform the selection;
        // G toggles the Edit grid.
        if (rl::is_key_pressed(rl::RLKeyboardKey.D)) tools::set_active(tools::DRAW_BTN);
        if (rl::is_key_pressed(rl::RLKeyboardKey.F)) tools::set_active(tools::FILL_BTN);
        if (rl::is_key_pressed(rl::RLKeyboardKey.C)) tools::set_active(tools::CIRCLE_BTN);
        if (rl::is_key_pressed(rl::RLKeyboardKey.S)) tools::set_active(tools::SQUARE_BTN);
        if (rl::is_key_pressed(rl::RLKeyboardKey.R)) tiles::rotate_sel();
        if (rl::is_key_pressed(rl::RLKeyboardKey.X)) tiles::flip_x_sel();
        if (rl::is_key_pressed(rl::RLKeyboardKey.Y)) tiles::flip_y_sel();
        if (rl::is_key_pressed(rl::RLKeyboardKey.G)) tiles::toggle_grid();
        return;
    }

    // Ctrl shortcuts: copy/cut/paste, undo/redo. With the mouse over the Edit pane
    // these act on the pixel selection; over the View they act on the tile shape.
    if (rl::is_key_pressed(rl::RLKeyboardKey.C)) {
        if (tiles::editor_hovered()) { tiles::pixel_copy(); } else { tiles::copy_sel(); }
    }
    if (rl::is_key_pressed(rl::RLKeyboardKey.X)) {
        if (tiles::editor_hovered()) { tiles::pixel_cut(); } else { tiles::cut_sel(); }
    }
    if (rl::is_key_pressed(rl::RLKeyboardKey.V)) {
        if (tiles::editor_hovered()) { tiles::pixel_paste(); } else { tiles::paste(); }
    }
    if (rl::is_key_pressed(rl::RLKeyboardKey.Z)) tiles::undo();
    if (rl::is_key_pressed(rl::RLKeyboardKey.Y)) tiles::redo();

    if (rl::is_key_pressed(rl::RLKeyboardKey.EQUAL) || rl::is_key_pressed(rl::RLKeyboardKey.KP_ADD))      set_scale(win_scale + 1);
    if (rl::is_key_pressed(rl::RLKeyboardKey.MINUS) || rl::is_key_pressed(rl::RLKeyboardKey.KP_SUBTRACT)) set_scale(win_scale - 1);
    if (rl::is_key_pressed(rl::RLKeyboardKey.ZERO))                                                       set_scale(1);

    // Ctrl 1..9 jumps straight to that scale. set_scale clamps to [1, max_scale],
    // so an unreachable level simply lands on the largest that fits the monitor.
    if (rl::is_key_pressed(rl::RLKeyboardKey.ONE))   set_scale(1);
    if (rl::is_key_pressed(rl::RLKeyboardKey.TWO))   set_scale(2);
    if (rl::is_key_pressed(rl::RLKeyboardKey.THREE)) set_scale(3);
    if (rl::is_key_pressed(rl::RLKeyboardKey.FOUR))  set_scale(4);
    if (rl::is_key_pressed(rl::RLKeyboardKey.FIVE))  set_scale(5);
    if (rl::is_key_pressed(rl::RLKeyboardKey.SIX))   set_scale(6);
    if (rl::is_key_pressed(rl::RLKeyboardKey.SEVEN)) set_scale(7);
    if (rl::is_key_pressed(rl::RLKeyboardKey.EIGHT)) set_scale(8);
    if (rl::is_key_pressed(rl::RLKeyboardKey.NINE))  set_scale(9);
}

fn void main() {
    // Scaling is locked: the window is not user-resizable. Scale is driven only
    // programmatically (Ctrl +/-, and the future "scale 1x" toolbar control).
    rl::init_window(400, 300, "Yet another tile editor"); // temp size; resized below
    defer rl::close_window();

    set_app_icon();

    // The default font is loaded now, so measure the toolbar to derive the
    // reference (minimum) design size. We deliberately do NOT use WINDOW_HIGHDPI:
    // on Wayland fractional scaling it desyncs screen/render sizes and offsets
    // the viewport. Without it, screen == render == framebuffer, so the layout
    // fills the window exactly. Units are device pixels; the window is opened
    // larger than the minimum below so it is comfortable on hi-res monitors.
    layout::configure(toolbar::natural_width());

    rl::set_window_min_size((int)layout::ref_w, (int)layout::ref_h);

    // Open at a comfortable default: the largest whole scale whose height sits
    // within ~70% of the monitor height (set_scale clamps to [1, max_scale]).
    float target_h = (float)rl::get_monitor_height(rl::get_current_monitor()) * 0.7f;
    set_scale((int)(target_h / layout::ref_h));

    rl::set_target_fps(60);

    while (!rl::window_should_close()) {
        handle_input();

        // The window stays on-ratio, but render through the centred fit viewport
        // anyway as a safety net: it absorbs any 1px rounding so the content is
        // never stretched, and keeps things correct during a mid-drag frame.
        Rect view = layout::fit_viewport(rl::get_screen_width(), rl::get_screen_height());
        layout::Layout l = layout::compute(view);

        rl::begin_drawing();
        rl::clear_background(BG_APP);

        int clicked = toolbar::draw(l.toolbar, SCALE_LABELS[win_scale - 1]);
        if (clicked == toolbar::SCALE_BTN) cycle_scale();
        if (clicked == toolbar::NEW_BTN)       new_file();
        if (clicked == toolbar::OPEN_BTN)      open_file();
        if (clicked == toolbar::SAVE_BTN)      tiles::save();
        if (clicked == toolbar::EXTEND_BTN)    tiles::extend();
        if (clicked == toolbar::TRIM_LEAD_BTN) tiles::trim_lead();
        if (clicked == toolbar::TRIM_TAIL_BTN) tiles::trim_tail();
        if (clicked == toolbar::SHRINK_BTN)    tiles::shrink();
        if (clicked == toolbar::COMPRESS_BTN)  compress_file();

        tiles::draw_preview(l.preview);
        tiles::draw_editor(l.editor, tools::active());
        int tool = tools::draw(l.tools, tiles::grid_on());
        if (tool == tools::ROTATE_BTN) tiles::rotate_sel();
        if (tool == tools::FLIPX_BTN)  tiles::flip_x_sel();
        if (tool == tools::FLIPY_BTN)  tiles::flip_y_sel();
        if (tool == tools::GRID_BTN)   tiles::toggle_grid();
        caption(l.preview, "VIEW");
        caption(l.editor,  "EDIT");

        palette::draw(l.palette);

        rl::end_drawing();
    }
}