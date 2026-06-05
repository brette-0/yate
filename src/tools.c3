// The editing-tool column: a stack of square buttons to the right of the editor.
//
// Each button is a one-letter shortcut for an edit mode. For now they only draw
// (with hover/press feedback) and report clicks; the modes are not wired up yet.
//
//   D -> Draw     F -> Fill      C -> Circle    S -> Square
//   R -> Rotate   X -> Mirror X  Y -> Mirror Y  G -> Grid (toggle)
module yate::tools;

import raylib6::rl;
import std::math; // for Rect
import yate::ui;

const RLColor BTN        = { 44,  46,  52,  255 }; // idle fill
const RLColor BTN_HOV    = { 58,  61,  70,  255 }; // hovered fill
const RLColor BTN_DN     = { 34,  36,  42,  255 }; // pressed fill
const RLColor BTN_ON     = { 46,  74,  58,  255 }; // active toggle fill (green tint)
const RLColor BTN_LN     = { 70,  73,  80,  255 }; // idle outline
const RLColor BTN_LN_HOV = { 96,  100, 110, 255 }; // hovered/pressed/active outline
const RLColor TEXT       = { 200, 205, 215, 255 };
const RLColor TOOL_SEL   = { 255, 165, 60,  255 }; // active-tool marching ants (orange)

const int FONT = 14;

const ZString[8] LABELS = { "D", "F", "C", "S", "R", "X", "Y", "G" };

// Button indices. D/F/C/S are mutually-exclusive drawing tools (one stays active,
// shown with the orange box); R/X/Y are one-shot actions; G toggles the grid.
const int DRAW_BTN   = 0;
const int FILL_BTN   = 1;
const int CIRCLE_BTN = 2;
const int SQUARE_BTN = 3; // last of the tool modes
const int ROTATE_BTN = 4;
const int FLIPX_BTN  = 5;
const int FLIPY_BTN  = 6;
const int GRID_BTN   = (int)LABELS.len - 1; // 7

// The currently selected drawing tool (one of DRAW_BTN..SQUARE_BTN).
int active_tool = DRAW_BTN;

// The active drawing tool, for the editor to dispatch on.
fn int active() => active_tool;

// Switch the active drawing tool. Out-of-range values are ignored, so callers
// (e.g. the D/F/C/S keyboard shortcuts) can pass an index straight through.
fn void set_active(int t) {
    if (t >= DRAW_BTN && t <= SQUARE_BTN) active_tool = t;
}

// Draw the tool column inside `area` (one button per label, stacked, square).
// `grid_on` highlights the grid toggle. Returns the index of a button the user
// just released a left-click on, or -1.
fn int draw(Rect area, bool grid_on) {
    int   n  = LABELS.len;
    float bh = area.height / (float)n; // each cell is square: area.width == bh
    int   font = (int)ui::px((float)FONT);

    RLVector2 mouse = rl::get_mouse_position();
    bool down     = rl::is_mouse_button_down(rl::RLMouseButton.LEFT);
    bool released = rl::is_mouse_button_released(rl::RLMouseButton.LEFT);

    int clicked = -1;
    foreach (i, label : LABELS) {
        Rect btn = { .x = area.x, .y = area.y + (float)i * bh, .width = area.width, .height = bh };

        bool active = (int)i == GRID_BTN && grid_on;
        bool hover  = rl::check_collision_point_rec(mouse, btn);
        RLColor fill = active ? BTN_ON : BTN;
        RLColor line = active ? BTN_LN_HOV : BTN_LN;
        if (hover) {
            fill = down ? BTN_DN : BTN_HOV;
            line = BTN_LN_HOV;
            if (released) {
                if ((int)i <= SQUARE_BTN) {
                    active_tool = (int)i; // pick a tool mode
                } else {
                    clicked = (int)i;     // one-shot action
                }
            }
        }

        rl::draw_rectangle_rec(btn, fill);
        rl::draw_rectangle_lines_ex(btn, ui::px(1), line);

        float tw = (float)rl::measure_text(label, font);
        Rect t = ui::place(btn, tw, (float)font, ui::Align.CENTER, ui::Align.CENTER);
        rl::draw_text(label, (int)t.x, (int)t.y, font, TEXT);
    }

    // Orange marching-ants box marking the active drawing tool (D/F/C/S only).
    Rect abtn = { .x = area.x, .y = area.y + (float)active_tool * bh, .width = area.width, .height = bh };
    ui::dots(ui::inset(abtn, -ui::px(1)), TOOL_SEL, (float)rl::get_time() * ui::px(24));

    return clicked;
}
