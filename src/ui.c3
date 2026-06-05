// Scalable layout toolkit for yate.
//
// Everything is authored in *logical units*. `scale` is one uniform factor
// (set each frame by layout::compute = window_width / design_width); multiply
// by it via `px()` to get physical pixels. Because the window's aspect ratio
// is locked, this single factor scales the whole UI proportionally.
module yate::ui;

import raylib6::rl;
import std::math; // for Rect (= Rectangle{float})

// Global uniform scale. Owned/updated by layout::compute.
float scale = 1.0;

// Logical units -> physical pixels.
fn float px(float logical) => logical * scale;

// --- Rect helpers (operate in physical pixels) -------------------------------

// Inset (pad) a rect equally on all sides. Negative `p` grows it.
fn Rect inset(Rect r, float p) {
    return { .x = r.x + p, .y = r.y + p, .width = r.width - 2.0f * p, .height = r.height - 2.0f * p };
}

// The result of carving a rect into a piece (`a`) and a remainder (`b`).
struct Split {
    Rect a; // the carved-off piece
    Rect b; // what's left
}

fn Split split_left(Rect r, float w) {
    Split s;
    s.a = { .x = r.x,     .y = r.y, .width = w,           .height = r.height };
    s.b = { .x = r.x + w, .y = r.y, .width = r.width - w, .height = r.height };
    return s;
}

fn Split split_right(Rect r, float w) {
    Split s;
    s.a = { .x = r.x + r.width - w, .y = r.y, .width = w,           .height = r.height };
    s.b = { .x = r.x,               .y = r.y, .width = r.width - w, .height = r.height };
    return s;
}

fn Split split_top(Rect r, float h) {
    Split s;
    s.a = { .x = r.x, .y = r.y,     .width = r.width, .height = h };
    s.b = { .x = r.x, .y = r.y + h, .width = r.width, .height = r.height - h };
    return s;
}

fn Split split_bottom(Rect r, float h) {
    Split s;
    s.a = { .x = r.x, .y = r.y + r.height - h, .width = r.width, .height = h };
    s.b = { .x = r.x, .y = r.y,                .width = r.width, .height = r.height - h };
    return s;
}

// --- Alignment ---------------------------------------------------------------

enum Align {
    START,
    CENTER,
    END
}

fn float align_offset(float outer, float inner, Align a) {
    if (a == Align.CENTER) return (outer - inner) * 0.5f;
    if (a == Align.END)    return outer - inner;
    return 0.0f; // START
}

// Place a child box of size (w, h) inside `parent`, aligned on each axis.
fn Rect place(Rect parent, float w, float h, Align ax, Align ay) {
    return {
        .x = parent.x + align_offset(parent.width, w, ax),
        .y = parent.y + align_offset(parent.height, h, ay),
        .width = w,
        .height = h,
    };
}

// --- Marching ants -----------------------------------------------------------

// Point at arc-length `s` clockwise from the top-left corner of `r`'s perimeter.
fn RLVector2 perim_point(Rect r, float s) {
    if (s < r.width)  return { r.x + s, r.y };
    s -= r.width;
    if (s < r.height) return { r.x + r.width, r.y + s };
    s -= r.height;
    if (s < r.width)  return { r.x + r.width - s, r.y + r.height };
    s -= r.width;
    return { r.x, r.y + r.height - s };
}

// A dotted outline around `r`. `offset` slides the dots along the perimeter;
// animate it (e.g. with time) for marching ants, or pass 0 for a static box.
fn void dots(Rect r, RLColor col, float offset) {
    float step  = px(6);
    float dot   = px(2);
    float perim = 2.0f * (r.width + r.height);

    // Reduce offset into [0, step) so the loop starts just inside the perimeter.
    float o = offset - (float)((int)(offset / step)) * step;

    for (float s = o; s < perim; s += step) {
        RLVector2 p = perim_point(r, s);
        Rect d = { .x = p.x - dot * 0.5f, .y = p.y - dot * 0.5f, .width = dot, .height = dot };
        rl::draw_rectangle_rec(d, col);
    }
}
