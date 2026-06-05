// Top toolbar region: a row of labelled buttons.
//
// The toolbar's intrinsic width (sum of button widths) DRIVES the window's
// design width -- the window is exactly as long as the toolbar.
module yate::toolbar;

import raylib6::rl;
import std::math; // for Rect
import yate::ui;

const RLColor BG     		= { 24,	 25,  28,  255 };
const RLColor BORDER 		= { 60,  63,  70,  255 };
const RLColor BTN    		= { 44,  46,  52,  255 }; // idle fill
const RLColor BTN_HOV 		= { 58,  61,  70,  255 }; // hovered fill
const RLColor BTN_DN  		= { 34,  36,  42,  255 }; // pressed fill
const RLColor BTN_LN 		= { 70,  73,  80,  255 };
const RLColor BTN_LN_HOV 	= { 96,  100, 110, 255 }; // hovered/pressed outline
const RLColor TEXT   		= { 200, 205, 215, 255 };

// Layout constants, in logical units.
const int   FONT = 12;
const float PAD  = 6.0;  // toolbar edge padding (left + right)
const float TPAD = 10.0; // horizontal text padding inside each button
const float BGAP = 4.0;  // gap between buttons

const ZString[9] LABELS = {
    "new", "open", "save", "extend",
    "trim lead", "trim tail", "shrink", "compress",
    "scale 1x",
};

// Indices of the buttons the app acts on. SCALE_BTN is derived from the array so
// it stays correct if the button list changes.
const int NEW_BTN       = 0;
const int OPEN_BTN      = 1;
const int SAVE_BTN      = 2;
const int EXTEND_BTN    = 3;
const int TRIM_LEAD_BTN = 4;
const int TRIM_TAIL_BTN = 5;
const int SHRINK_BTN    = 6;
const int COMPRESS_BTN  = 7;
const int SCALE_BTN     = (int)LABELS.len - 1;

// Intrinsic toolbar width in LOGICAL units (i.e. at scale = 1). The design
// width is set from this, so the window matches the toolbar's length exactly.
fn float natural_width()
{
    float total = PAD * 2.0f;
    foreach (i, label : LABELS) {
        if (i > 0) total += BGAP;
        total += (float)rl::measure_text(label, FONT) + TPAD * 2.0f;
    }
    return total;
}

// Draw the toolbar. `scale_label` overrides the text of the scale button.
// Returns the index of a button the user just released a left-click on, or -1.
fn int draw(Rect r, ZString scale_label) {
    rl::draw_rectangle_rec(r, BG);
    Rect divider = { .x = r.x, .y = r.y + r.height - ui::px(1), .width = r.width, .height = ui::px(1) };
    rl::draw_rectangle_rec(divider, BORDER);

    float pad = ui::px(PAD);
    float gap = ui::px(BGAP);
    int font = (int)ui::px((float)FONT);

    float h = r.height - pad * 2.0f;
    float y = r.y + pad;

    // Buttons stretch: divide the full toolbar width into n equal cells.
    int n = LABELS.len;
    float avail = r.width - pad * 2.0f - gap * (float)(n - 1);
    float bw = avail / (float)n;

    RLVector2 mouse = rl::get_mouse_position();
    bool down = rl::is_mouse_button_down(rl::RLMouseButton.LEFT);
    bool released = rl::is_mouse_button_released(rl::RLMouseButton.LEFT);

    int clicked = -1;
    foreach (i, label : LABELS)
    {
        float x = r.x + pad + (bw + gap) * (float)i;

        Rect btn = { .x = x, .y = y, .width = bw, .height = h };

        ZString text = (int)i == SCALE_BTN ? scale_label : label;

        bool hover = rl::check_collision_point_rec(mouse, btn);
        RLColor fill = BTN;
        RLColor line = BTN_LN;
        if (hover) {
            fill = down ? BTN_DN : BTN_HOV;
            line = BTN_LN_HOV;
            if (released) clicked = (int)i;
        }

        rl::draw_rectangle_rec(btn, fill);
        rl::draw_rectangle_lines_ex(btn, ui::px(1), line);

        float tw = (float)rl::measure_text(text, font);
        Rect t = ui::place(btn, tw, (float)font, ui::Align.CENTER, ui::Align.CENTER);
        rl::draw_text(text, (int)t.x, (int)t.y, font, TEXT);
    }
    return clicked;
}
