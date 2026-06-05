// Window layout geometry for yate.
//
// The window resizes freely to *any* size. Everything is recomputed from the
// live window dimensions every frame -- there is no fixed design canvas and no
// aspect lock. The three rules the layout enforces:
//
//   * Toolbar buttons STRETCH to divide the full window width (see toolbar.c3).
//   * Preview + editor are the two largest equal squares that fit two-across in
//     the space between the toolbar and the palette, with no padding around
//     them beyond the gaps that separate the chrome.
//   * The palette band is CONFINED to its selector: its height is exactly what
//     the 16x4 NES grid of square cells needs at the current width.
//
// A reference size (ref_w x ref_h), measured once at startup, is used only to
// derive the uniform UI scale (font sizes, border thickness, gaps) so the
// chrome stays proportionate as the window grows or shrinks.
module yate::layout;

import raylib6::rl;
import std::math; // for Rect
import yate::ui;

// --- Chrome dimensions (logical units, multiplied by ui::scale at runtime) ---
const float GAP       = 8.0;  // gap between squares and around chrome
const float TOOLBAR_H = 38.0; // toolbar band height
const float LABEL_H   = 18.0; // caption strip above the squares
const float PAL_PAD   = 8.0;  // padding inside the palette band
const float PAL_GAP   = 8.0;  // gap between the selector and active halves
const int   TOOLS     = 8;    // tool buttons stacked beside the editor square

// --- Reference size, set once at startup from the toolbar's natural width ----
float ref_w;
float ref_h;

fn void configure(float toolbar_w) {
    ref_w = toolbar_w;
    float sq = square_side(ref_w, 1.0f);
    float pal = palette_height(ref_w, 1.0f);
    ref_h = TOOLBAR_H + GAP + LABEL_H + sq + GAP + pal;
}

// Side of the two equal squares at window width `w` and scale `s`. The row holds,
// left to right: gap, square, gap, square, gap, tools column, gap. The tools
// column is one button wide (== square / TOOLS), so solving the width budget:
//   w = 4*gap + 2*square + square/TOOLS  ->  square = (w - 4*gap)*TOOLS/(2*TOOLS+1)
fn float square_side(float w, float s) {
    float gap = GAP * s;
    return (w - 4.0f * gap) * (float)TOOLS / (float)(2 * TOOLS + 1);
}

// Palette band height at window width `w` and scale `s`: the selector is a 16x4
// grid of square cells filling the left half, so four cell-rows + padding.
fn float palette_height(float w, float s) {
    float pad = PAL_PAD * s;
    float gap = PAL_GAP * s;
    float left_half = (w - 2.0f * pad - gap) * 0.5f;
    float cell = left_half / 16.0f;
    return cell * 4.0f + 2.0f * pad;
}

struct Layout {
    Rect toolbar;
    Rect preview;
    Rect editor;
    Rect tools;
    Rect palette;
}

// The locked design aspect ratio (width : height).
fn float aspect() => ref_w / ref_h;

// The largest aspect-correct rectangle that fits inside the window, centred.
// Returns it as a Rect (x/y = top-left margin offset). The UI is rendered into
// this viewport so the content is *always* aspect-constrained and fully filled,
// regardless of the window's actual shape -- any leftover becomes uniform
// background margin rather than broken, stretched empty space.
fn Rect fit_viewport(int screen_w, int screen_h) {
    float w = (float)screen_w;
    float h = (float)screen_h;
    float a = aspect();

    float vw;
    float vh;
    if (w / h > a) {
        vh = h;          // window is too wide: height is the limit
        vw = h * a;
    } else {
        vw = w;          // window is too tall: width is the limit
        vh = w / a;
    }
    return { .x = (w - vw) * 0.5f, .y = (h - vh) * 0.5f, .width = vw, .height = vh };
}

fn Layout compute(Rect view) {
    float ox = view.x;
    float oy = view.y;
    float w  = view.width;
    float h  = view.height;

    // The viewport is aspect-correct, so a single uniform scale fits both axes.
    float s = w / ref_w;
    ui::scale = s;

    float gap   = GAP * s;
    float tb_h  = TOOLBAR_H * s;
    float lbl_h = LABEL_H * s;

    // Palette confined to its selector.
    float pal_h = palette_height(w, s);

    // Middle region: from below the caption strip down to the palette.
    float mid_top = tb_h + gap + lbl_h;
    float mid_h   = h - mid_top - pal_h - gap;
    if (mid_h < 1.0f) mid_h = 1.0f;

    // Two-across equal squares plus a one-button-wide tools column on the right.
    float square = square_side(w, s);
    if (square > mid_h) square = mid_h;
    float tools_w = square / (float)TOOLS;

    float ed_x = ox + gap + square + gap;

    Layout l;
    l.toolbar = { .x = ox,                          .y = oy,             .width = w,       .height = tb_h };
    l.preview = { .x = ox + gap,                    .y = oy + mid_top,   .width = square,  .height = square };
    l.editor  = { .x = ed_x,                        .y = oy + mid_top,   .width = square,  .height = square };
    l.tools   = { .x = ed_x + square + gap,         .y = oy + mid_top,   .width = tools_w, .height = square };
    l.palette = { .x = ox,                          .y = oy + h - pal_h, .width = w,       .height = pal_h };
    return l;
}
