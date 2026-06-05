// Loaded CHR graphics: the tile data being edited, plus the preview grid.
//
// A tile is an 8x8 cell at 2bpp in the classic NES CHR layout: 16 bytes each,
// the first 8 the low bitplane, the next 8 the high bitplane. Pixels are indices
// 0..3 into whichever palette is selected bottom-right, so the whole preview
// re-colours live when you pick a different palette.
//
// Opening a file discards the current scene immediately (no save). The file must
// be a whole number of 64-byte units, otherwise the open is aborted and the
// scene is left empty -- we never keep a partially-valid or stale scene.
module yate::tiles;

import raylib6::rl;
import std::math; // for Rect
import yate::ui;
import yate::nes;
import yate::palette;

const int TILE_BYTES = 16;          // 8x8 @ 2bpp
const int UNIT       = TILE_BYTES;  // a valid file is a whole number of tiles (16 bytes)
const int GRID       = 16;          // the View shows a GRID x GRID page of tiles
const int PAGE       = GRID * GRID; // 256 tiles visible at once
const int NEW_TILES  = 512;         // a fresh file: 512 tiles == 8 KiB CHR

// Edit tools -- must match the button order in yate::tools.
const int TOOL_DRAW   = 0;
const int TOOL_FILL   = 1;
const int TOOL_CIRCLE = 2;
const int TOOL_SQUARE = 3;

char* data;          // raw CHR bytes (heap), or null when nothing is loaded
usz   data_len;
int   tile_count;    // data_len / TILE_BYTES
int   sel;           // selected tile index (top-left of the selection block)
int   scroll_row;    // index of the first visible tile-row
int   sel_dim = 1;   // selection size in tiles per side (1..GRID), wheel-adjustable
bool  show_grid = true; // overlay a per-pixel grid in the Edit pane (tools 'G' toggle)
bool  sb_drag;       // scrollbar is being dragged: track the mouse Y until release

char[4096] file_path; // path the current scene was opened/created from
bool       has_file;  // whether file_path holds a valid on-disk path

// Square tool drag, in block-pixel coordinates (0..bw*8, 0..bh*8). Defined while
// the button is held, committed on release.
bool sq_active;
int  sq_x0;
int  sq_y0;
int  sq_x1;
int  sq_y1;

// Multi-select (shift-click): a set of absolute tile indices forming a free shape.
// The anchor is the least-column/least-row corner of the set; copy captures each
// tile's bytes plus its offset from that anchor.
const int SEL_MAX = GRID * GRID; // a page's worth of selectable tiles
int       msel_count;
int[SEL_MAX] msel;               // absolute tile indices currently multi-selected

// Clipboard: the copied shape. Each entry is a tile's bytes plus its (dcol, drow)
// offset from the anchor; paste re-anchors the whole shape onto the tile cursor.
const int CLIP_MAX = GRID * GRID;
int       clip_count;
int[CLIP_MAX] clip_dcol;
int[CLIP_MAX] clip_drow;
char[CLIP_MAX * TILE_BYTES] clip_px;
bool      pasted; // a paste has happened: the next shift-click starts a fresh selection

// Cut (Ctrl+X) turns paste into a MOVE: the source tiles are cleared once the
// shape lands, and the source re-homes to the paste site so a further paste keeps
// moving it. cut_src_(col,row) is the source shape's anchor in the 16-wide layout.
bool cut_mode;
int  cut_src_col;
int  cut_src_row;

// One-deep undo of the last action. Two kinds share the slot:
//   PIXELS -- a content edit (draw, fill, shape, transform, paste, clear). A
//             snapshot records the touched tiles' bytes BEFORE and AFTER; undo
//             swaps to BEFORE, redo to AFTER.
//   DELETE -- a tile was removed (middle-click on an empty tile). undo re-inserts
//             the saved tile at its old index; redo excises it again.
// Other structural ops (extend/trim/shrink) still invalidate undo outright.
// undo_state: 0 none, 1 can-undo (just acted/redone), 2 can-redo (undone).
const int UNDO_KIND_PIXELS = 0;
const int UNDO_KIND_DELETE = 1;
const int UNDO_MAX = CLIP_MAX;
int       undo_kind;     // which of the two the held slot is
int       undo_count;
int[UNDO_MAX] undo_idx;
char[UNDO_MAX * TILE_BYTES] undo_prev;
char[UNDO_MAX * TILE_BYTES] undo_new;
int       undo_state;
int       undo_del_idx;             // DELETE: index the tile was removed from
char[TILE_BYTES] undo_del_bytes;    // DELETE: the removed tile's bytes, to restore

bool draw_active; // a freehand draw stroke is in progress (one undo step per stroke)

// --- Pixel selection / clipboard (Edit pane) ---------------------------------
// Shift-drag in the Edit pane marks a rectangular region of pixels; Ctrl+C/X copy
// or cut it to a pixel clipboard, and Ctrl+V stamps it at the pixel cursor. This
// is the View's tile copy/paste one zoom level down. Undo/redo are shared: pixel
// writes go through the same per-tile snapshot machinery as everything else.
const int PCLIP_SIDE = GRID * 8; // max block side in pixels (128)

// Free-form pixel selection: shift-drag paints a SHAPE -- an arbitrary set of
// pixels, not a rectangle -- into psel_mask. The stroke's first pixel decides
// whether it adds or removes, so dragging over selected pixels deselects them.
bool psel_drag;                          // a shift-drag is in progress
bool psel_add;                           // this stroke adds (true) or removes (false)
int  psel_count;                         // selected pixels (0 == nothing marked)
int  psel_lx;                            // last painted pixel this stroke (for line-fill)
int  psel_ly;
bool[PCLIP_SIDE * PCLIP_SIDE] psel_mask; // block-pixel set, indexed by y*PCLIP_SIDE + x

// Pixel clipboard: the copied shape as a mask + values within its bounding box,
// re-anchored onto the pixel cursor on paste -- the tile clipboard one zoom down.
bool pclip_on;                            // a stamp is ready to paste
int  pclip_w;                             // bounding-box size of the shape, in pixels
int  pclip_h;
bool[PCLIP_SIDE * PCLIP_SIDE] pclip_mask; // which box cells belong to the shape
char[PCLIP_SIDE * PCLIP_SIDE] pclip_px;   // their palette indices (box-local, row-major)
bool pclip_cut;                           // cut: clear the source shape on paste
int  pcut_x0;                             // source bounding-box top-left, for the cut
int  pcut_y0;
bool ppasted;                             // a paste happened: next shift-stroke resets

int  pcur_x;       // pixel cursor: where a paste stamps (its top-left)
int  pcur_y;
bool pcur_valid;   // the cursor is inside the Edit block this frame
bool edit_hover;   // the mouse is over the Edit pane (routes Ctrl+C/X/V to pixels)

const RLColor BG        = { 22,  23,  26,  255 }; // backdrop behind the grid
const RLColor BORDER    = { 60,  63,  70,  255 }; // empty-state outline
const RLColor LINE      = { 230, 234, 242, 255 }; // thin white separators / outline (Edit pane, scrollbar)
const RLColor VGRID     = { 18,  14,  22,  255 }; // View tile separators: an off-black the NES can't make, so green ants pop
const RLColor SELECT    = { 80,  220, 120, 255 }; // green marching ants on the selection
const RLColor PXGRID    = { 72,  76,  84,  255 }; // per-pixel grid; opaque so crossings don't double-blend
const RLColor MSEL_FILL = { 255, 255, 255, 90  }; // whiten multi-selected tiles
const RLColor ANCHOR    = { 255, 165, 60,  255 }; // orange anchor dot
const RLColor PASTE_LN  = { 255, 165, 60,  255 }; // paste-preview outline (tiles)
const RLColor PASTE_FILL = { 255, 165, 60, 110 }; // paste-preview fill (pixel shape)

extern fn void* fopen(ZString path, ZString mode) @cname("fopen");
extern fn int   fseek(void* s, long off, int whence) @cname("fseek");
extern fn long  ftell(void* s) @cname("ftell");
extern fn usz   fread(void* p, usz size, usz n, void* s) @cname("fread");
extern fn int   fclose(void* s) @cname("fclose");
extern fn usz   fwrite(void* p, usz size, usz n, void* s) @cname("fwrite");
extern fn void* malloc(usz n) @cname("malloc");
extern fn void* calloc(usz n, usz size) @cname("calloc");
extern fn void* realloc(void* p, usz n) @cname("realloc");
extern fn void* memset(void* p, int c, usz n) @cname("memset");
extern fn void* memmove(void* d, void* s, usz n) @cname("memmove");
extern fn void  free(void* p) @cname("free");

// Discard the current scene without saving.
fn void clear() {
    if (data != null) free(data);
    data = null;
    data_len = 0;
    tile_count = 0;
    sel = 0;
    scroll_row = 0;
    has_file = false;
    msel_count = 0;
    clip_count = 0;
    undo_count = 0;
    undo_state = 0;
    undo_kind = UNDO_KIND_PIXELS;
    draw_active = false;
    pasted = false;
    cut_mode = false;
    psel_drag = false;
    psel_clear();
    pclip_on = false;
    pclip_cut = false;
    ppasted = false;
    pcur_valid = false;
    edit_hover = false;
}

// Open a CHR file. Always discards the current scene first; on any problem the
// scene is simply left empty. Returns true only when a valid file was loaded.
fn bool load(ZString path) {
    clear();

    void* f = fopen(path, "rb");
    if (f == null) return false;

    fseek(f, 0, 2); // SEEK_END
    long nbytes = ftell(f);
    fseek(f, 0, 0); // SEEK_SET

    // Must be a non-empty whole number of 64-byte units.
    if (nbytes <= 0 || nbytes % UNIT != 0) { fclose(f); return false; }

    char* buf = (char*)malloc((usz)nbytes);
    if (buf == null) { fclose(f); return false; }

    usz got = fread(buf, 1, (usz)nbytes, f);
    fclose(f);
    if (got != (usz)nbytes) { free(buf); return false; }

    data = buf;
    data_len = (usz)nbytes;
    tile_count = (int)(data_len / TILE_BYTES);

    // Remember where we loaded from, so save() can overwrite it in place.
    usz i = 0;
    while (path[i] != 0 && i < (usz)file_path.len - 1) { file_path[i] = path[i]; i++; }
    file_path[i] = 0;
    has_file = true;
    return true;
}

// Create a brand-new CHR file at `path`: NEW_TILES tiles of pure emptiness
// (all-zero bytes, == 8 KiB). Overwrites any existing file. On success the new
// scene is loaded for editing; on any failure the scene is left empty.
fn bool create(ZString path) {
    clear();

    usz nbytes = (usz)(NEW_TILES * TILE_BYTES);
    char* zeros = (char*)calloc(nbytes, 1);
    if (zeros == null) return false;

    void* f = fopen(path, "wb");
    if (f == null) { free(zeros); return false; }

    usz wrote = fwrite(zeros, 1, nbytes, f);
    free(zeros);
    fclose(f);
    if (wrote != nbytes) return false;

    return load(path);
}

fn bool loaded() => data != null;

// Overwrite the opened file with the current scene, in place. No dialog and no
// confirmation -- it writes the moment it is called. Does nothing if there is no
// loaded scene or no remembered path.
fn bool save() {
    if (data == null || !has_file) return false;

    void* f = fopen((ZString)&file_path[0], "wb");
    if (f == null) return false;

    usz wrote = fwrite(data, 1, data_len, f);
    fclose(f);
    return wrote == data_len;
}

// RLE-encode `n` bytes of `src` into `dst`, returning the encoded length. Stream
// is read until a 0x00 terminator: 0x01..0x7F L = literal of L bytes; 0x81..0xFF
// R B = byte B repeated (R & 0x7F) times. Runs and literals are capped at 127, so
// the worst case adds ~1 byte per 127 -- the caller sizes `dst` with margin.
fn usz rle_encode(char* src, usz n, char* dst) {
    usz i = 0;
    usz o = 0;
    while (i < n) {
        usz run = 1;
        while (i + run < n && src[i + run] == src[i] && run < 127) run++;

        if (run >= 2) {
            dst[o++] = (char)(0x80 | run);
            dst[o++] = src[i];
            i += run;
            continue;
        }

        // Gather a literal until a run (>=2) starts or we hit the 127 cap.
        usz start = i;
        usz len = 0;
        while (i < n && len < 127) {
            usz r = 1;
            while (i + r < n && src[i + r] == src[i] && r < 3) r++;
            if (r >= 2) break;
            i++;
            len++;
        }
        dst[o++] = (char)len;
        for (usz k = 0; k < len; k++) dst[o++] = src[start + k];
    }
    dst[o++] = 0x00;
    return o;
}

// Export the scene to `path` as an RLE stream. The in-memory scene is untouched.
fn bool compress(ZString path) {
    if (data == null) return false;

    usz cap = data_len + data_len / 100 + 64; // worst-case margin
    char* buf = malloc(cap);
    if (buf == null) return false;

    usz enc = rle_encode(data, data_len, buf);

    void* f = fopen(path, "wb");
    if (f == null) { free(buf); return false; }
    usz wrote = fwrite(buf, 1, enc, f);
    fclose(f);
    free(buf);
    return wrote == enc;
}

// Suggest a name for the export: "_rle" inserted before the opened file's
// extension (foo.chr -> foo_rle.chr), appended if none, "untitled_rle.chr" if
// no file is open. The extension dot is the last '.' after the final '/'.
fn void suggest_rle_name(char* out, usz cap) {
    if (cap == 0) return;

    if (!has_file) {
        ZString fallback = "untitled_rle.chr";
        usz k = 0;
        while (fallback[k] != 0 && k < cap - 1) { out[k] = fallback[k]; k++; }
        out[k] = 0;
        return;
    }

    usz len = 0;
    while (file_path[len] != 0) len++;

    usz slash = 0;
    bool have_slash = false;
    for (usz k = 0; k < len; k++) {
        if (file_path[k] == '/') { slash = k; have_slash = true; }
    }

    usz dot = len;
    for (usz k = 0; k < len; k++) {
        if (file_path[k] == '.' && (!have_slash || k > slash)) dot = k;
    }

    usz o = 0;
    for (usz k = 0; k < dot && o < cap - 1; k++) out[o++] = file_path[k];
    ZString tag = "_rle";
    for (usz k = 0; tag[k] != 0 && o < cap - 1; k++) out[o++] = tag[k];
    for (usz k = dot; k < len && o < cap - 1; k++) out[o++] = file_path[k];
    out[o] = 0;
}

// Grow the in-memory scene so the tile count reaches the next multiple of
// NEW_TILES; if it is already a multiple, add a whole NEW_TILES more. The new
// tiles are zeroed; the growth lands on disk on the next save().
fn bool extend() {
    if (data == null) return false;

    int add       = NEW_TILES - (tile_count % NEW_TILES); // 1..NEW_TILES (==NEW_TILES when aligned)
    int new_tiles = tile_count + add;
    usz new_len   = (usz)new_tiles * TILE_BYTES;

    char* grown = (char*)realloc(data, new_len);
    if (grown == null) return false; // original buffer left intact on failure

    memset(grown + data_len, 0, new_len - data_len); // zero the fresh tiles

    data = grown;
    data_len = new_len;
    tile_count = new_tiles;
    undo_state = 0; // tile indices/contents changed: the paste undo no longer applies
    return true;
}

// True when every byte of tile `t` is zero (all-transparent, presumed unused).
fn bool tile_empty(int t) {
    usz base = (usz)t * TILE_BYTES;
    for (int i = 0; i < TILE_BYTES; i++) {
        if (data[base + (usz)i] != 0) return false;
    }
    return true;
}

// Keep the leftmost `new_count` tiles already sitting at the front of the buffer
// and shrink to fit. The caller is responsible for having moved kept tiles down.
fn void resize_to(int new_count) {
    if (new_count < 1) new_count = 1; // never produce a zero-tile (unloadable) file

    usz new_len = (usz)new_count * TILE_BYTES;
    char* shrunk = (char*)realloc(data, new_len);
    if (shrunk != null) data = shrunk; // a shrinking realloc keeps the data either way

    data_len = new_len;
    tile_count = new_count;

    if (sel >= tile_count) sel = tile_count - 1;
    int ms = max_scroll();
    if (scroll_row > ms) scroll_row = ms;

    // A structural change renumbers tiles, so the multi-select and paste undo
    // (both keyed by absolute index) no longer line up -- drop them. The pixel
    // marquee is tied to the old block layout too, so it goes; the pixel
    // clipboard is position-independent raw pixels, so it stays.
    msel_count = 0;
    undo_state = 0;
    psel_drag = false;
    psel_clear();
}

// trim lead: drop every empty tile at the FRONT of the file, stopping at the first
// non-empty tile. Pairs with extend to carve a file down to a custom size.
fn bool trim_lead() {
    if (data == null) return false;

    int first = 0;
    while (first < tile_count && tile_empty(first)) first++;
    if (first <= 0) return false; // front tile is already non-empty: nothing to do

    int keep = tile_count - first;       // tiles to retain
    int drop = tile_count - (keep < 1 ? 1 : keep);
    memmove(data, data + (usz)drop * TILE_BYTES, (usz)(tile_count - drop) * TILE_BYTES);
    resize_to(tile_count - drop);
    return true;
}

// trim tail: drop every empty tile at the END of the file, stopping at the last
// non-empty tile. Kept tiles are already at the front, so we only shrink.
fn bool trim_tail() {
    if (data == null) return false;

    int last = tile_count; // exclusive bound of kept tiles
    while (last > 0 && tile_empty(last - 1)) last--;
    if (last >= tile_count) return false; // tail tile is already non-empty

    resize_to(last);
    return true;
}

// shrink: remove EVERY empty tile regardless of position, compacting the rest to
// the front. More destructive than the trims (it renumbers interior tiles), but
// the most thorough way to reclaim space.
fn bool shrink() {
    if (data == null) return false;

    int w = 0; // write cursor: next slot for a kept tile
    for (int rd = 0; rd < tile_count; rd++) {
        if (tile_empty(rd)) continue;
        if (w != rd) memmove(data + (usz)w * TILE_BYTES, data + (usz)rd * TILE_BYTES, TILE_BYTES);
        w++;
    }
    if (w == tile_count) return false; // no empty tiles anywhere

    resize_to(w); // w may be 0 (all empty) -> resize_to keeps one tile
    return true;
}

// Blank a single tile in place (all bytes to zero) without changing the tile count.
fn void clear_tile(int t) {
    if (data == null || t < 0 || t >= tile_count) return;
    memset(data + (usz)t * TILE_BYTES, 0, TILE_BYTES);
}

// Raw single-tile excision: compact the tail down over tile `t` and shrink by one,
// clamping sel/scroll. Touches neither the undo slot nor the selections -- callers
// arrange those. Assumes a valid `t` and tile_count >= 2.
fn void excise_tile(int t) {
    int tail = tile_count - t - 1;
    if (tail > 0) {
        memmove(data + (usz)t * TILE_BYTES, data + (usz)(t + 1) * TILE_BYTES, (usz)tail * TILE_BYTES);
    }
    usz new_len = (usz)(tile_count - 1) * TILE_BYTES;
    char* shrunk = (char*)realloc(data, new_len); // shrinking realloc keeps data either way
    if (shrunk != null) data = shrunk;
    data_len = new_len;
    tile_count -= 1;
    if (sel >= tile_count) sel = tile_count - 1;
    if (sel < 0) sel = 0;
    int msx = max_scroll();
    if (scroll_row > msx) scroll_row = msx;
}

// Insert one empty tile at index `at`, shifting tiles from there on up by one and
// growing the buffer. Used by undo to reverse a deletion. No undo/selection
// bookkeeping -- the caller owns that.
fn bool insert_empty_tile(int at) {
    if (data == null) return false;
    if (at < 0) at = 0;
    if (at > tile_count) at = tile_count;

    usz new_len = (usz)(tile_count + 1) * TILE_BYTES;
    char* grown = (char*)realloc(data, new_len);
    if (grown == null) return false; // original buffer left intact on failure
    data = grown;

    int tail = tile_count - at;
    if (tail > 0) {
        memmove(data + (usz)(at + 1) * TILE_BYTES, data + (usz)at * TILE_BYTES, (usz)tail * TILE_BYTES);
    }
    memset(data + (usz)at * TILE_BYTES, 0, TILE_BYTES);
    data_len = new_len;
    tile_count += 1;
    return true;
}

// Delete a single tile, compacting everything after it down by one -- as if shrink
// had swallowed just this tile. Tiles past `t` are renumbered, same as shrink. The
// removed tile's bytes are saved and a DELETE undo is armed, so the deletion can be
// reversed (undo re-inserts it). Refuses to remove the last remaining tile.
fn bool remove_tile(int t) {
    if (data == null || t < 0 || t >= tile_count || tile_count <= 1) return false;

    usz base = (usz)t * TILE_BYTES;
    for (int b = 0; b < TILE_BYTES; b++) undo_del_bytes[b] = data[base + (usz)b];

    excise_tile(t);

    // The renumbering invalidates the index-keyed selections; drop them. The pixel
    // clipboard is position-independent, so it stays.
    msel_count = 0;
    psel_drag = false;
    psel_clear();

    undo_kind    = UNDO_KIND_DELETE;
    undo_del_idx = t;
    undo_state   = 1;
    return true;
}

// Per-pixel Edit-grid toggle, driven by the 'G' tool button.
fn bool grid_on() => show_grid;
fn void toggle_grid() { show_grid = !show_grid; }

// Decode pixel (x, y) of tile `t` to its 2bpp palette index (0..3).
fn char pixel(int t, int x, int y) {
    usz base = (usz)t * TILE_BYTES;
    char lo  = data[base + (usz)y];
    char hi  = data[base + (usz)y + 8];
    int  bit = 7 - x;
    return (char)(((lo >> bit) & 1) | (((hi >> bit) & 1) << 1));
}

// Write 2bpp value `val` (0..3) into pixel (x, y) of tile `t`, splitting it back
// across the low/high bitplanes.
fn void set_pixel(int t, int x, int y, char val) {
    usz  base = (usz)t * TILE_BYTES;
    int  bit  = 7 - x;
    char m    = (char)(1 << bit);
    char clr  = (char)~m;
    if (val & 1) { data[base + (usz)y]     |= m; } else { data[base + (usz)y]     &= clr; }
    if (val & 2) { data[base + (usz)y + 8] |= m; } else { data[base + (usz)y + 8] &= clr; }
}

// Map a selection-block cell (column dc, row dr within the sel_dim x sel_dim
// block) to an absolute tile index. The block is ALWAYS a full square: rather than
// clamp at an edge, it wraps -- columns modulo the 16-wide layout (X), rows modulo
// the file's row count (Y) -- so a selection at the right/bottom edge stays square
// by folding the overflow back to the opposite side. Independent of the View's
// scroll, so the Edit pane always tracks the selection, not what's on screen.
fn int block_tile(int dc, int dr) {
    int rows = (tile_count + GRID - 1) / GRID; // total file rows
    if (rows < 1) rows = 1;
    int sc  = sel % GRID;
    int sr  = sel / GRID;
    int col = ((sc + dc) % GRID + GRID) % GRID;
    int row = ((sr + dr) % rows + rows) % rows;
    return row * GRID + col;
}

// 2bpp value of block-pixel (bx, by), or -1 when it falls outside the block or on
// a tile past the file end. Those -1 cells act as hard walls for the flood fill.
fn int block_pixel(int bx, int by, int w, int h) {
    if (bx < 0 || by < 0 || bx >= w || by >= h) return -1;
    int t = block_tile(bx / 8, by / 8);
    if (t >= tile_count) return -1;
    return (int)pixel(t, bx % 8, by % 8);
}

// Flood fill from block-pixel (sx, sy): recolour the contiguous region of the
// clicked colour with the pen, across tile seams, within the selection block.
//
// Connectivity is strictly 4-way (up/down/left/right). Diagonals are deliberately
// NOT connected, so a same-colour pixel reachable only on the diagonal is a hard
// barrier -- the colour can't leak through a corner. At NES resolution this is the
// expected fill behaviour:  E S / S T  fills T without touching E.
fn void fill_at(int sx, int sy, int bw, int bh) {
    if (data == null) return;

    int w = bw * 8;
    int h = bh * 8;

    int target = block_pixel(sx, sy, w, h);
    if (target < 0) return; // clicked an empty/non-existent cell

    char pen = (char)palette::selected_color();
    if ((int)pen == target) return; // nothing to do

    // Explicit stack + seen set (no recursion). Pixels matching `target` recolour
    // to `pen`; since pen != target, the region can't be re-entered once filled.
    bool[GRID * 8 * GRID * 8] seen;
    int[GRID * 8 * GRID * 8]  stack;
    int sp = 0;

    stack[sp++] = sy * w + sx;
    seen[sy * w + sx] = true;

    while (sp > 0) {
        int idx = stack[--sp];
        int bx  = idx % w;
        int by  = idx / w;

        int t = block_tile(bx / 8, by / 8);
        set_pixel(t, bx % 8, by % 8, pen);

        int[4] nx = { bx - 1, bx + 1, bx, bx };
        int[4] ny = { by, by, by - 1, by + 1 };
        for (int k = 0; k < 4; k++) {
            int ax = nx[k];
            int ay = ny[k];
            if (ax < 0 || ay < 0 || ax >= w || ay >= h) continue;
            int ni = ay * w + ax;
            if (seen[ni]) continue;
            if (block_pixel(ax, ay, w, h) != target) continue; // wall / different colour
            seen[ni] = true;
            stack[sp++] = ni;
        }
    }
}

// --- Multi-select / clipboard / paste undo -----------------------------------

// Is absolute tile `t` already in the multi-select set?
fn bool sel_contains(int t) {
    for (int i = 0; i < msel_count; i++) {
        if (msel[i] == t) return true;
    }
    return false;
}

// Add the current sel_dim x sel_dim selection block (anchored at `sel`, wrapping
// at the edges via block_tile) to the multi-select set, de-duplicating and
// skipping any cell that maps past the file end.
fn void add_block_to_sel() {
    for (int dr = 0; dr < sel_dim; dr++) {
        for (int dc = 0; dc < sel_dim; dc++) {
            int t = block_tile(dc, dr);
            if (t >= tile_count) continue;
            if (sel_contains(t)) continue;
            if (msel_count >= SEL_MAX) return;
            msel[msel_count++] = t;
        }
    }
}

// Drop tile `t` from the multi-select set (swap-with-last, order is irrelevant).
fn void remove_from_sel(int t) {
    for (int i = 0; i < msel_count; i++) {
        if (msel[i] == t) {
            msel[i] = msel[msel_count - 1];
            msel_count--;
            return;
        }
    }
}

// Shift-click toggle. If the clicked block's anchor tile is already selected, the
// whole block is removed from the selection; otherwise it is added. This lets a
// shift-click on an already-registered tile de-select it.
fn void toggle_block_in_sel() {
    bool present = sel_contains(block_tile(0, 0));
    for (int dr = 0; dr < sel_dim; dr++) {
        for (int dc = 0; dc < sel_dim; dc++) {
            int t = block_tile(dc, dr);
            if (t >= tile_count) continue;
            if (present) {
                remove_from_sel(t);
            } else if (!sel_contains(t) && msel_count < SEL_MAX) {
                msel[msel_count++] = t;
            }
        }
    }
}

// Copy/cut the multi-select shape to the clipboard. Falls back to the current
// selection block if nothing was shift-selected. The anchor is the least-column,
// least-row corner; each entry stores its offset from it plus the tile's bytes.
// `cut` arms the move behaviour (paste clears the source). The selection visuals
// then clear, giving way to the paste preview.
fn void cut_or_copy(bool cut) {
    if (data == null) return;

    if (msel_count == 0) add_block_to_sel();
    if (msel_count == 0) return;

    int amin_c = msel[0] % GRID;
    int amin_r = msel[0] / GRID;
    for (int i = 0; i < msel_count; i++) {
        int c = msel[i] % GRID;
        int r = msel[i] / GRID;
        if (c < amin_c) amin_c = c;
        if (r < amin_r) amin_r = r;
    }

    clip_count = 0;
    for (int i = 0; i < msel_count; i++) {
        int c = msel[i] % GRID;
        int r = msel[i] / GRID;
        clip_dcol[clip_count] = c - amin_c;
        clip_drow[clip_count] = r - amin_r;
        usz src = (usz)msel[i] * TILE_BYTES;
        usz dst = (usz)clip_count * TILE_BYTES;
        for (int b = 0; b < TILE_BYTES; b++) clip_px[dst + (usz)b] = data[src + (usz)b];
        clip_count++;
    }

    cut_mode    = cut;
    cut_src_col = amin_c; // where the source lives, so paste can clear it on a cut
    cut_src_row = amin_r;
    pasted      = false;  // a fresh shape is not spent yet
    msel_count  = 0;      // the anchor is now invisible; the paste preview takes over
}

fn void copy_sel() => cut_or_copy(false); // Ctrl+C: paste leaves the source intact
fn void cut_sel()  => cut_or_copy(true);  // Ctrl+X: paste moves, clearing the source

// Is absolute tile `st` one of the paste destinations for cursor (sc, sr)? Used so
// a cut never erases a source tile that the paste just wrote over.
fn bool clip_is_dest(int st, int sc, int sr) {
    for (int i = 0; i < clip_count; i++) {
        int tc = sc + clip_dcol[i];
        int tr = sr + clip_drow[i];
        if (tc < 0 || tc >= GRID || tr < 0) continue;
        int dt = tr * GRID + tc;
        if (dt >= tile_count) continue;
        if (dt == st) return true;
    }
    return false;
}

// --- Undo snapshot ----------------------------------------------------------
// snap_reset/snap_add capture the BEFORE bytes of the tiles an action will touch;
// snap_commit then captures their AFTER bytes and arms the undo. Call snap_reset +
// snap_add(s) BEFORE editing, snap_commit AFTER.

// Is tile `t` already in the pending snapshot?
fn bool snap_has(int t) {
    for (int i = 0; i < undo_count; i++) {
        if (undo_idx[i] == t) return true;
    }
    return false;
}

// Begin a fresh snapshot.
fn void snap_reset() { undo_count = 0; }

// Record tile `t`'s current bytes as its BEFORE state (de-duped; past-end skipped).
fn void snap_add(int t) {
    if (t < 0 || t >= tile_count) return;
    if (snap_has(t)) return;
    if (undo_count >= UNDO_MAX) return;
    usz src = (usz)t * TILE_BYTES;
    usz dst = (usz)undo_count * TILE_BYTES;
    for (int b = 0; b < TILE_BYTES; b++) undo_prev[dst + (usz)b] = data[src + (usz)b];
    undo_idx[undo_count] = t;
    undo_count++;
}

// Snapshot every tile of the current selection block (what the Edit window shows).
fn void snap_add_block() {
    for (int dr = 0; dr < sel_dim; dr++) {
        for (int dc = 0; dc < sel_dim; dc++) snap_add(block_tile(dc, dr));
    }
}

// Capture the snapshot tiles' current bytes as the AFTER state and arm the undo.
fn void snap_commit() {
    if (undo_count == 0) { undo_state = 0; return; }
    for (int i = 0; i < undo_count; i++) {
        int t = undo_idx[i];
        usz src = (usz)t * TILE_BYTES;
        usz dst = (usz)i * TILE_BYTES;
        for (int b = 0; b < TILE_BYTES; b++) undo_new[dst + (usz)b] = data[src + (usz)b];
    }
    undo_kind  = UNDO_KIND_PIXELS;
    undo_state = 1;
}

// Paste the clipboard shape with its anchor re-pinned onto the tile cursor (sel).
// Each entry lands at (selCol + dcol, selRow + drow); cells that fall off-grid or
// past the file end are skipped. A cut is a one-shot MOVE: the source tiles are
// cleared and the clipboard is then dropped, so only the first paste lands. The
// overwritten and cleared tiles are snapshotted as one undo step.
fn void paste() {
    if (data == null || clip_count == 0) return;

    int sc = sel % GRID;
    int sr = sel / GRID;

    // Snapshot every affected tile FIRST (destinations, plus the cut sources we'll
    // clear), so BEFORE is the pre-paste state even when tiles are touched twice.
    snap_reset();
    for (int i = 0; i < clip_count; i++) {
        int tc = sc + clip_dcol[i];
        int tr = sr + clip_drow[i];
        if (tc < 0 || tc >= GRID || tr < 0) continue;
        snap_add(tr * GRID + tc);
    }
    if (cut_mode) {
        for (int i = 0; i < clip_count; i++) {
            int scc = cut_src_col + clip_dcol[i];
            int srr = cut_src_row + clip_drow[i];
            if (scc < 0 || scc >= GRID || srr < 0) continue;
            snap_add(srr * GRID + scc);
        }
    }

    // Write the shape to the destination.
    for (int i = 0; i < clip_count; i++) {
        int tc = sc + clip_dcol[i];
        int tr = sr + clip_drow[i];
        if (tc < 0 || tc >= GRID || tr < 0) continue;
        int t = tr * GRID + tc;
        if (t < 0 || t >= tile_count) continue;
        usz dst = (usz)t * TILE_BYTES;
        usz cpx = (usz)i * TILE_BYTES;
        for (int b = 0; b < TILE_BYTES; b++) data[dst + (usz)b] = clip_px[cpx + (usz)b];
    }

    // Cut: blank each source tile the paste didn't already overwrite, then drop the
    // clipboard -- a cut moves the shape exactly once, so later pastes do nothing.
    if (cut_mode) {
        for (int i = 0; i < clip_count; i++) {
            int scc = cut_src_col + clip_dcol[i];
            int srr = cut_src_row + clip_drow[i];
            if (scc < 0 || scc >= GRID || srr < 0) continue;
            int st = srr * GRID + scc;
            if (st < 0 || st >= tile_count) continue;
            if (clip_is_dest(st, sc, sr)) continue; // don't erase what we just wrote
            usz s = (usz)st * TILE_BYTES;
            for (int b = 0; b < TILE_BYTES; b++) data[s + (usz)b] = 0;
        }
        clip_count = 0;     // the shape is consumed: no preview, no further paste
        cut_mode   = false;
    }

    snap_commit();
    pasted = true; // the shape is now spent: the next shift-click resets selection
}

// Undo the last action (Ctrl+Z). A DELETE undo re-inserts the removed tile at its
// old index and restores its bytes; a PIXELS undo restores the snapshot's BEFORE.
fn void undo() {
    if (data == null || undo_state != 1) return;

    if (undo_kind == UNDO_KIND_DELETE) {
        if (insert_empty_tile(undo_del_idx)) {
            usz base = (usz)undo_del_idx * TILE_BYTES;
            for (int b = 0; b < TILE_BYTES; b++) data[base + (usz)b] = undo_del_bytes[b];
        }
        undo_state = 2;
        return;
    }

    for (int i = 0; i < undo_count; i++) {
        int t = undo_idx[i];
        if (t < 0 || t >= tile_count) continue;
        usz dst = (usz)t * TILE_BYTES;
        usz up  = (usz)i * TILE_BYTES;
        for (int b = 0; b < TILE_BYTES; b++) data[dst + (usz)b] = undo_prev[up + (usz)b];
    }
    undo_state = 2;
}

// Redo the last undone action (Ctrl+Y). A DELETE redo excises the tile again; a
// PIXELS redo re-applies the snapshot's AFTER bytes.
fn void redo() {
    if (data == null || undo_state != 2) return;

    if (undo_kind == UNDO_KIND_DELETE) {
        if (undo_del_idx >= 0 && undo_del_idx < tile_count && tile_count > 1) {
            excise_tile(undo_del_idx);
        }
        undo_state = 1;
        return;
    }

    for (int i = 0; i < undo_count; i++) {
        int t = undo_idx[i];
        if (t < 0 || t >= tile_count) continue;
        usz dst = (usz)t * TILE_BYTES;
        usz up  = (usz)i * TILE_BYTES;
        for (int b = 0; b < TILE_BYTES; b++) data[dst + (usz)b] = undo_new[up + (usz)b];
    }
    undo_state = 1;
}

// --- Pixel selection / clipboard --------------------------------------------

// True while the mouse is over the Edit pane: the Ctrl+C/X/V handlers use this to
// route the clipboard to pixels (in the editor) vs. tiles (in the View).
fn bool editor_hovered() => edit_hover;

// Empty the pixel selection (clears the whole mask, not just the count).
fn void psel_clear() {
    psel_count = 0;
    memset(&psel_mask[0], 0, (usz)(PCLIP_SIDE * PCLIP_SIDE));
}

// Read/write one cell of the selection mask, bounds-checked.
fn bool psel_get(int x, int y) {
    if (x < 0 || y < 0 || x >= PCLIP_SIDE || y >= PCLIP_SIDE) return false;
    return psel_mask[y * PCLIP_SIDE + x];
}
fn void psel_set(int x, int y, bool on) {
    if (x < 0 || y < 0 || x >= PCLIP_SIDE || y >= PCLIP_SIDE) return;
    int idx = y * PCLIP_SIDE + x;
    if (on && !psel_mask[idx])  { psel_mask[idx] = true;  psel_count++; }
    if (!on && psel_mask[idx])  { psel_mask[idx] = false; psel_count--; }
}

// Paint a line of selection cells between two pixels (Bresenham), so a fast drag
// leaves no gaps in the shape.
fn void psel_line(int x0, int y0, int x1, int y1, bool on) {
    int dx = x1 - x0; if (dx < 0) dx = -dx;
    int dy = y1 - y0; if (dy < 0) dy = -dy;
    int sx = x0 < x1 ? 1 : -1;
    int sy = y0 < y1 ? 1 : -1;
    int err = dx - dy;
    int x = x0;
    int y = y0;
    while (true) {
        psel_set(x, y, on);
        if (x == x1 && y == y1) break;
        int e2 = 2 * err;
        if (e2 > -dy) { err -= dy; x += sx; }
        if (e2 <  dx) { err += dx; y += sy; }
    }
}

// Copy (or cut) the selected pixel SHAPE to the clipboard. Stored as a mask +
// values within its bounding box (anchored at the least-x/least-y cell), read
// through block_tile so it spans tile seams. The selection clears, giving way to
// the paste preview. No-op when nothing is selected.
fn void pixel_cut_or_copy(bool cut) {
    if (data == null || psel_count == 0) return;

    int w = sel_dim * 8;
    int h = sel_dim * 8;

    // Bounding box of the selected shape.
    int xlo = w; int ylo = h; int xhi = -1; int yhi = -1;
    for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
            if (!psel_mask[y * PCLIP_SIDE + x]) continue;
            if (x < xlo) xlo = x;
            if (x > xhi) xhi = x;
            if (y < ylo) ylo = y;
            if (y > yhi) yhi = y;
        }
    }
    if (xhi < 0) return; // nothing inside the current block

    pclip_w = xhi - xlo + 1;
    pclip_h = yhi - ylo + 1;
    for (int i = 0; i < pclip_w * pclip_h; i++) pclip_mask[i] = false;
    for (int y = ylo; y <= yhi; y++) {
        for (int x = xlo; x <= xhi; x++) {
            if (!psel_mask[y * PCLIP_SIDE + x]) continue;
            int li = (y - ylo) * pclip_w + (x - xlo);
            int t  = block_tile(x / 8, y / 8);
            pclip_mask[li] = true;
            pclip_px[li]   = t < tile_count ? pixel(t, x % 8, y % 8) : 0;
        }
    }

    pclip_on  = true;
    pclip_cut = cut;
    pcut_x0   = xlo;     // where the source shape lives, so a cut can clear it
    pcut_y0   = ylo;
    ppasted   = false;   // a fresh stamp is not spent yet
    psel_clear();        // the selection gives way to the paste preview
}

fn void pixel_copy() => pixel_cut_or_copy(false); // Ctrl+C in the editor
fn void pixel_cut()  => pixel_cut_or_copy(true);  // Ctrl+X in the editor

// Does the shape, re-anchored at (dx, dy), cover absolute block-pixel (sx, sy)?
// Used so a cut never erases a source pixel the paste just wrote over.
fn bool pclip_dest_has(int sx, int sy, int dx, int dy) {
    int qx = sx - dx;
    int qy = sy - dy;
    if (qx < 0 || qy < 0 || qx >= pclip_w || qy >= pclip_h) return false;
    return pclip_mask[qy * pclip_w + qx];
}

// Stamp the clipboard shape with its bounding box re-anchored at the pixel cursor.
// Only masked, in-bounds pixels are written -- nothing else is touched. A cut is a
// one-shot MOVE: source pixels the stamp didn't cover are cleared and the
// clipboard dropped. Every touched tile snapshots as one shared undo step.
fn void pixel_paste() {
    if (data == null || !pclip_on || !pcur_valid) return;

    int w  = sel_dim * 8;
    int h  = sel_dim * 8;
    int dx = pcur_x;
    int dy = pcur_y;

    // Snapshot destinations, plus the cut sources we'll clear, BEFORE writing.
    snap_reset();
    for (int py = 0; py < pclip_h; py++) {
        for (int px = 0; px < pclip_w; px++) {
            if (!pclip_mask[py * pclip_w + px]) continue;
            int bx = dx + px;
            int by = dy + py;
            if (bx < 0 || by < 0 || bx >= w || by >= h) continue;
            snap_add(block_tile(bx / 8, by / 8));
        }
    }
    if (pclip_cut) {
        for (int py = 0; py < pclip_h; py++) {
            for (int px = 0; px < pclip_w; px++) {
                if (!pclip_mask[py * pclip_w + px]) continue;
                int bx = pcut_x0 + px;
                int by = pcut_y0 + py;
                if (bx < 0 || by < 0 || bx >= w || by >= h) continue;
                snap_add(block_tile(bx / 8, by / 8));
            }
        }
    }

    // Write the shape.
    for (int py = 0; py < pclip_h; py++) {
        for (int px = 0; px < pclip_w; px++) {
            if (!pclip_mask[py * pclip_w + px]) continue;
            int bx = dx + px;
            int by = dy + py;
            if (bx < 0 || by < 0 || bx >= w || by >= h) continue;
            int t = block_tile(bx / 8, by / 8);
            if (t < tile_count) set_pixel(t, bx % 8, by % 8, pclip_px[py * pclip_w + px]);
        }
    }

    // Cut: blank source pixels the stamp didn't land on, then drop the clipboard.
    if (pclip_cut) {
        for (int py = 0; py < pclip_h; py++) {
            for (int px = 0; px < pclip_w; px++) {
                if (!pclip_mask[py * pclip_w + px]) continue;
                int sx = pcut_x0 + px;
                int sy = pcut_y0 + py;
                if (sx < 0 || sy < 0 || sx >= w || sy >= h) continue;
                if (pclip_dest_has(sx, sy, dx, dy)) continue; // don't erase what we wrote
                int t = block_tile(sx / 8, sy / 8);
                if (t < tile_count) set_pixel(t, sx % 8, sy % 8, 0);
            }
        }
        pclip_on  = false;
        pclip_cut = false;
    }

    snap_commit();
    ppasted = true; // the stamp is spent: the next shift-stroke starts fresh
}

// --- Tile transforms ---------------------------------------------------------
// Each acts on every tile of the current selection block, transformed in place.

fn void rotate_sel() { apply_block(0); } // 90 degrees clockwise, once per call
fn void flip_x_sel() { apply_block(1); } // mirror horizontally
fn void flip_y_sel() { apply_block(2); } // mirror vertically

// Transform the selection as ONE image: a bw x bh block of tiles becomes a single
// (bw*8) x (bh*8) picture, so the tiles are both re-arranged and their pixels
// transformed. op: 0 = rotate 90 clockwise, 1 = mirror X, 2 = mirror Y.
fn void apply_block(int op) {
    if (data == null || sel >= tile_count) return;

    // One undo step covering the whole transformed block.
    snap_reset();
    snap_add_block();

    // The block is always a full sel_dim x sel_dim square; cells map through
    // block_tile, which wraps at the edges rather than clamping.
    int bw = sel_dim;
    int bh = sel_dim;

    int w = bw * 8; // block size in pixels
    int h = bh * 8;

    // Snapshot the whole block as one pixel image (missing tiles read as 0).
    char[GRID * 8 * GRID * 8] src;
    for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
            int  t = block_tile(x / 8, y / 8);
            char v = 0;
            if (t < tile_count) v = pixel(t, x % 8, y % 8);
            src[y * w + x] = v;
        }
    }

    // Destination footprint: a 90 degree rotation swaps the two dimensions.
    int nw = op == 0 ? h : w;
    int nh = op == 0 ? w : h;

    for (int y = 0; y < nh; y++) {
        for (int x = 0; x < nw; x++) {
            int sx = 0;
            int sy = 0;
            if (op == 0) {
                sx = y;         sy = h - 1 - x; // rotate 90 CW: new(x,y)=old(y,h-1-x)
            } else if (op == 1) {
                sx = w - 1 - x; sy = y;         // mirror X
            } else {
                sx = x;         sy = h - 1 - y; // mirror Y
            }

            int t = block_tile(x / 8, y / 8);
            if (t >= tile_count) continue; // skip cells past the file end
            set_pixel(t, x % 8, y % 8, src[sy * w + sx]);
        }
    }

    snap_commit();
}

// Draw tile `t` filling `r`, recoloured through the selected palette. Pixel rects
// are computed from exact boundaries so they tile with no sub-pixel seams.
fn void draw_tile(int t, Rect r) {
    for (int y = 0; y < 8; y++) {
        float y0 = r.y + r.height * (float)y / 8.0f;
        float y1 = r.y + r.height * (float)(y + 1) / 8.0f;
        for (int x = 0; x < 8; x++) {
            float x0 = r.x + r.width * (float)x / 8.0f;
            float x1 = r.x + r.width * (float)(x + 1) / 8.0f;
            Rect p = { .x = x0, .y = y0, .width = x1 - x0, .height = y1 - y0 };
            rl::draw_rectangle_rec(p, palette::tile_color((int)pixel(t, x, y)));
        }
    }
}

// Highest valid scroll_row so the last row of tiles can reach the bottom.
fn int max_scroll() {
    int rows = (tile_count + GRID - 1) / GRID; // ceil
    int m = rows - GRID;
    return m < 0 ? 0 : m;
}

// The left View: a GRID x GRID page of tiles, thin white separators, a white
// outline around the data, a green marching-ants box on the selection block
// (sel_dim x sel_dim tiles), and a scrollbar when the file holds more than a page.
fn void draw_preview(Rect area) {
    if (data == null) {
        rl::draw_rectangle_rec(area, BG);
        rl::draw_rectangle_lines_ex(area, ui::px(1), BORDER);
        return;
    }

    bool  scroll = tile_count > PAGE;
    float sb_w   = scroll ? ui::px(10) : 0.0f;

    // Square GRID x GRID grid, fit to the space left of the scrollbar.
    float avail = area.width - sb_w - ui::px(4);
    float side  = avail < area.height ? avail : area.height;
    float tile  = side / (float)GRID;
    float gx    = area.x;
    float gy    = area.y;
    Rect  grid  = { .x = gx, .y = gy, .width = tile * (float)GRID, .height = tile * (float)GRID };

    handle_input(area, grid, tile);

    rl::draw_rectangle_rec(grid, BG);

    int first = scroll_row * GRID;
    for (int i = 0; i < PAGE; i++) {
        int t = first + i;
        if (t >= tile_count) break;
        float tx = gx + (float)(i % GRID) * tile;
        float ty = gy + (float)(i / GRID) * tile;
        draw_tile(t, { .x = tx, .y = ty, .width = tile, .height = tile });
    }

    // Thin white separators + outline, drawn ONLY around cells that hold data.
    // The last visible row may be partial, so the boundary steps in there rather
    // than tracing a full 16x16 square -- that makes the file's end unambiguous.
    int vis = tile_count - first;        // tiles on this page
    if (vis > PAGE) vis = PAGE;
    int fr  = vis / GRID;                // number of full rows
    int rem = vis % GRID;                // tiles in the partial last row
    int rows = fr + (rem > 0 ? 1 : 0);

    // Vertical lines: each spans down only as far as a column it borders exists.
    for (int k = 0; k <= GRID; k++) {
        int span = fr + ((rem > 0 && k <= rem) ? 1 : 0);
        if (span == 0) continue;
        float x = gx + (float)k * tile;
        rl::draw_line_ex({ x, gy }, { x, gy + (float)span * tile }, ui::px(1), VGRID);
    }

    // Horizontal lines: each spans across the widest of its two adjacent rows.
    for (int k = 0; k <= rows; k++) {
        int above = (k - 1 < 0) ? 0 : (k - 1 < fr ? GRID : (k - 1 == fr && rem > 0 ? rem : 0));
        int below = (k < fr) ? GRID : (k == fr && rem > 0 ? rem : 0);
        int cols  = above > below ? above : below;
        if (cols == 0) continue;
        float y = gy + (float)k * tile;
        rl::draw_line_ex({ gx, y }, { gx + (float)cols * tile, y }, ui::px(1), VGRID);
    }

    // Green marching ants around the selection block. The block is always a full
    // sel_dim square; running off the right edge wraps to the left columns and off
    // the bottom wraps to the top rows, so it can appear as up to four page-clipped
    // pieces (matching block_tile). Each visible piece gets its own ants outline.
    {
        int nrows = (tile_count + GRID - 1) / GRID;
        if (nrows < 1) nrows = 1;
        int sc = sel % GRID;
        int sr = sel / GRID;
        float off = (float)rl::get_time() * ui::px(24);

        int[2] xc0; int[2] xc1; int xn = 0; // column ranges [c0, c1)
        xc0[xn] = sc;
        xc1[xn] = sc + sel_dim > GRID ? GRID : sc + sel_dim;
        xn++;
        if (sc + sel_dim > GRID) { xc0[xn] = 0; xc1[xn] = sc + sel_dim - GRID; xn++; }

        int[2] yr0; int[2] yr1; int yn = 0; // file-row ranges [r0, r1)
        yr0[yn] = sr;
        yr1[yn] = sr + sel_dim > nrows ? nrows : sr + sel_dim;
        yn++;
        if (sr + sel_dim > nrows) { yr0[yn] = 0; yr1[yn] = sr + sel_dim - nrows; yn++; }

        for (int yi = 0; yi < yn; yi++) {
            int pr0 = yr0[yi] - scroll_row; // file rows -> page rows
            int pr1 = yr1[yi] - scroll_row;
            if (pr0 < 0)    pr0 = 0;
            if (pr1 > GRID) pr1 = GRID;
            if (pr1 <= pr0) continue;
            for (int xi = 0; xi < xn; xi++) {
                Rect box = { .x = gx + (float)xc0[xi] * tile, .y = gy + (float)pr0 * tile,
                             .width  = (float)(xc1[xi] - xc0[xi]) * tile,
                             .height = (float)(pr1 - pr0) * tile };
                ui::dots(box, SELECT, off);
            }
        }
    }

    // Multi-select shape: whiten each selected tile on the page and mark the
    // anchor (least-column/least-row corner) with an orange dot in that cell.
    if (msel_count > 0) {
        int amin_c = msel[0] % GRID;
        int amin_r = msel[0] / GRID;
        for (int i = 0; i < msel_count; i++) {
            int c = msel[i] % GRID;
            int rr = msel[i] / GRID;
            if (c < amin_c)  amin_c = c;
            if (rr < amin_r) amin_r = rr;
            int t = msel[i];
            if (t < first || t >= first + PAGE) continue;
            int vi = t - first;
            float tx = gx + (float)(vi % GRID) * tile;
            float ty = gy + (float)(vi / GRID) * tile;
            rl::draw_rectangle_rec({ tx, ty, tile, tile }, MSEL_FILL);
        }
        int at = amin_r * GRID + amin_c;
        if (at >= first && at < first + PAGE) {
            int vi = at - first;
            float ax = gx + (float)(vi % GRID) * tile;
            float ay = gy + (float)(vi / GRID) * tile;
            float rad = tile * 0.18f;
            rl::draw_circle_v({ ax + rad + ui::px(2), ay + rad + ui::px(2) }, rad, ANCHOR);
        }
    }

    // Paste preview: the clipboard shape's outline (not its pixels) re-anchored on
    // the tile cursor, so you can see where a Ctrl+V will land. Persists until the
    // next copy.
    if (clip_count > 0) {
        int sc = sel % GRID;
        int sr = sel / GRID;
        for (int i = 0; i < clip_count; i++) {
            int tc = sc + clip_dcol[i];
            int tr = sr + clip_drow[i];
            if (tc < 0 || tc >= GRID || tr < 0) continue;
            int t = tr * GRID + tc;
            if (t < first || t >= first + PAGE) continue;
            int vi = t - first;
            float tx = gx + (float)(vi % GRID) * tile;
            float ty = gy + (float)(vi / GRID) * tile;
            rl::draw_rectangle_lines_ex({ tx, ty, tile, tile }, ui::px(1), PASTE_LN);
        }
    }

    if (scroll) draw_scrollbar({ .x = area.x + area.width - sb_w, .y = gy, .width = sb_w, .height = grid.height });
}

// Wheel over the View sizes the selection block (sel_dim tiles per side, 1..GRID);
// click selects the tile under the cursor as the block's top-left anchor.
fn void handle_input(Rect area, Rect grid, float tile) {
    RLVector2 mouse = rl::get_mouse_position();

    if (rl::check_collision_point_rec(mouse, area)) {
        float wheel = rl::get_mouse_wheel_move();
        if (wheel != 0.0f) {
            sel_dim += (int)wheel; // scroll up -> larger selection
            if (sel_dim < 1)    sel_dim = 1;
            if (sel_dim > GRID) sel_dim = GRID;
        }
    }

    if (sb_drag) return; // a scrollbar drag owns the pointer; ignore tile clicks

    // Left-click selects the tile under the cursor as the block anchor. Holding
    // shift keeps it a normal click but also toggles the selection block in the
    // multi-select shape (click a selected tile to drop it); a plain click clears
    // the shape. After a paste, the first shift-click discards the now-spent shape
    // (selection + clipboard preview) and starts fresh.
    if (rl::is_mouse_button_released(rl::RLMouseButton.LEFT)) {
        int t = tile_at(grid, tile, mouse);
        if (t >= 0) {
            sel = t;
            bool shift = rl::is_key_down(rl::RLKeyboardKey.LEFT_SHIFT)
                      || rl::is_key_down(rl::RLKeyboardKey.RIGHT_SHIFT);
            if (shift) {
                if (pasted) {
                    msel_count = 0;
                    clip_count = 0;
                    pasted = false;
                }
                toggle_block_in_sel();
            } else {
                msel_count = 0;
            }
        }
    }

    // Middle-click erases a tile: a drawn tile is blanked first; clicking an
    // already-empty tile removes it outright (compacting the rest down).
    if (rl::is_mouse_button_released(rl::RLMouseButton.MIDDLE)) {
        int t = tile_at(grid, tile, mouse);
        if (t >= 0) {
            if (tile_empty(t)) {
                remove_tile(t); // structural, but undoable: undo re-inserts the tile
            } else {
                snap_reset();
                snap_add(t);
                clear_tile(t);
                snap_commit();
            }
        }
    }
}

// Index of the tile under `mouse` within the visible page, or -1 if the cursor is
// off the grid or over an empty (past-the-end) cell.
fn int tile_at(Rect grid, float tile, RLVector2 mouse) {
    if (!rl::check_collision_point_rec(mouse, grid)) return -1;
    int col = (int)((mouse.x - grid.x) / tile);
    int row = (int)((mouse.y - grid.y) / tile);
    if (col < 0 || col >= GRID || row < 0 || row >= GRID) return -1;
    int t = (scroll_row + row) * GRID + col;
    return t < tile_count ? t : -1;
}

// A proportional scrollbar. Pressing anywhere on the track latches a drag; while
// latched it seeks to the mouse Y every frame until the button is released, even
// if the cursor wanders off the track horizontally -- smoother than requiring the
// pointer to stay over the bar. The latch (sb_drag) also suppresses tile selection
// and all Edit-pane input, so a scroll drag never spills into editing.
fn void draw_scrollbar(Rect track) {
    int ms = max_scroll();
    RLVector2 mouse = rl::get_mouse_position();

    if (rl::is_mouse_button_pressed(rl::RLMouseButton.LEFT) && rl::check_collision_point_rec(mouse, track)) {
        sb_drag = true;
    }
    if (!rl::is_mouse_button_down(rl::RLMouseButton.LEFT)) {
        sb_drag = false;
    }
    if (sb_drag && ms > 0) {
        float rel = (mouse.y - track.y) / track.height; // absolute seek to cursor Y
        int r = (int)(rel * (float)ms + 0.5f);
        scroll_row = r < 0 ? 0 : (r > ms ? ms : r);
    }

    rl::draw_rectangle_rec(track, BG);
    rl::draw_rectangle_lines_ex(track, ui::px(1), BORDER);

    int rows  = (tile_count + GRID - 1) / GRID;
    float frac = (float)GRID / (float)rows;          // visible fraction
    float th   = track.height * frac;
    if (th < ui::px(12)) th = ui::px(12);

    float ty = track.y + (ms > 0 ? (track.height - th) * (float)scroll_row / (float)ms : 0.0f);
    Rect thumb = { .x = track.x + ui::px(2), .y = ty, .width = track.width - ui::px(4), .height = th };
    rl::draw_rectangle_rec(thumb, LINE);
}

// Dispatch Edit-pane mouse input for the active `tool`. Geometry is the block's
// screen origin (ox, oy), pixel-cell size (cell), and tile dimensions (bw x bh).
fn void handle_edit_input(int tool, float ox, float oy, float cell, int bw, int bh) {
    if (sb_drag) return; // a scrollbar drag must never spill into editing

    int w = bw * 8;
    int h = bh * 8;
    float pxsz = cell / 8.0f;

    RLVector2 m = rl::get_mouse_position();
    int  bx = (int)((m.x - ox) / pxsz);
    int  by = (int)((m.y - oy) / pxsz);
    bool inside = m.x >= ox && m.y >= oy && bx < w && by < h; // bx,by >= 0 implied

    // Track the pixel cursor (clamped into the block) so a paste/preview can anchor
    // its top-left at it. Invalid while the cursor is outside the block.
    pcur_valid = inside;
    if (inside) {
        pcur_x = bx >= w ? w - 1 : bx;
        pcur_y = by >= h ? h - 1 : by;
    }

    bool shift = rl::is_key_down(rl::RLKeyboardKey.LEFT_SHIFT)
              || rl::is_key_down(rl::RLKeyboardKey.RIGHT_SHIFT);

    // Shift-drag PAINTS a free-form pixel shape (mirrors the View's shift-select)
    // and owns the pointer, so the drawing tools never fire while selecting. The
    // stroke's first pixel sets the sense: pressing an unselected pixel adds,
    // pressing a selected one removes -- so you can rub pixels back out. After a
    // paste the first shift-press discards the spent stamp and starts fresh.
    if (shift) {
        if (inside && rl::is_mouse_button_pressed(rl::RLMouseButton.LEFT)) {
            if (ppasted) { pclip_on = false; ppasted = false; psel_clear(); }
            psel_drag = true;
            psel_add  = !psel_get(pcur_x, pcur_y);
            psel_set(pcur_x, pcur_y, psel_add);
            psel_lx = pcur_x; psel_ly = pcur_y;
        }
        if (psel_drag && inside && rl::is_mouse_button_down(rl::RLMouseButton.LEFT)) {
            psel_line(psel_lx, psel_ly, pcur_x, pcur_y, psel_add);
            psel_lx = pcur_x; psel_ly = pcur_y;
        }
        if (psel_drag && rl::is_mouse_button_released(rl::RLMouseButton.LEFT)) {
            psel_drag = false;
        }
        return;
    }

    // A plain press in the pane clears the selection before a drawing tool acts.
    if (inside && rl::is_mouse_button_pressed(rl::RLMouseButton.LEFT)) psel_clear();

    // Square and Circle share the same drag: press anchors one corner, the moving
    // corner tracks the cursor, and the shape is committed on release. Only the
    // rasteriser differs (a box outline vs. an inscribed ellipse).
    if (tool == TOOL_SQUARE || tool == TOOL_CIRCLE) {
        if (inside && rl::is_mouse_button_pressed(rl::RLMouseButton.LEFT)) {
            sq_active = true;
            sq_x0 = bx; sq_y0 = by;
            sq_x1 = bx; sq_y1 = by;
        }
        if (sq_active && rl::is_mouse_button_down(rl::RLMouseButton.LEFT)) {
            sq_x1 = bx < 0 ? 0 : (bx >= w ? w - 1 : bx); // clamp the moving corner
            sq_y1 = by < 0 ? 0 : (by >= h ? h - 1 : by);
        }
        if (sq_active && rl::is_mouse_button_released(rl::RLMouseButton.LEFT)) {
            snap_reset();
            snap_add_block(); // the shape can land anywhere in the block
            if (tool == TOOL_CIRCLE) {
                circle_pixels(sq_x0, sq_y0, sq_x1, sq_y1, true, ox, oy, pxsz);
            } else {
                square_pixels(sq_x0, sq_y0, sq_x1, sq_y1, true, ox, oy, pxsz);
            }
            snap_commit();
            sq_active = false;
        }
        return;
    }

    // Fill: one flood fill per click (fires once, not while held).
    if (tool == TOOL_FILL) {
        if (inside && rl::is_mouse_button_pressed(rl::RLMouseButton.LEFT)) {
            snap_reset();
            snap_add_block(); // the fill may spread across the whole block
            fill_at(bx, by, bw, bh);
            snap_commit();
        }
        return;
    }

    // Freehand Draw: one undo step per stroke. Snapshot the whole Edit window at
    // mouse-down, paint the pen while held, and commit the snapshot on release.
    if (tool == TOOL_DRAW) {
        if (inside && rl::is_mouse_button_pressed(rl::RLMouseButton.LEFT)) {
            snap_reset();
            snap_add_block();
            draw_active = true;
        }
        if (draw_active && inside && rl::is_mouse_button_down(rl::RLMouseButton.LEFT)) {
            int t = block_tile(bx / 8, by / 8);
            if (t < tile_count) set_pixel(t, bx % 8, by % 8, (char)palette::selected_color());
        }
        if (draw_active && rl::is_mouse_button_released(rl::RLMouseButton.LEFT)) {
            snap_commit();
            draw_active = false;
        }
    }
}

// Walk the 1px border of the rectangle (x0,y0)-(x1,y1) in block-pixel coords. When
// `commit`, write the pen into the tile data; otherwise draw a live preview cell.
// The interior is never touched.
fn void square_pixels(int x0, int y0, int x1, int y1, bool commit, float ox, float oy, float pxsz) {
    int xlo = x0 < x1 ? x0 : x1;
    int xhi = x0 < x1 ? x1 : x0;
    int ylo = y0 < y1 ? y0 : y1;
    int yhi = y0 < y1 ? y1 : y0;

    char    pen = (char)palette::selected_color();
    RLColor col = palette::tile_color((int)pen);

    for (int by = ylo; by <= yhi; by++) {
        for (int bx = xlo; bx <= xhi; bx++) {
            if (bx != xlo && bx != xhi && by != ylo && by != yhi) continue; // border only
            if (commit) {
                int t = block_tile(bx / 8, by / 8);
                if (t < tile_count) set_pixel(t, bx % 8, by % 8, pen);
            } else {
                Rect r = { .x = ox + (float)bx * pxsz, .y = oy + (float)by * pxsz, .width = pxsz, .height = pxsz };
                rl::draw_rectangle_rec(r, col);
            }
        }
    }
}

// Is pixel (px, py) inside the filled ellipse centred at (cx, cy) with semi-axes
// (a, b)? Each pixel is sampled at its CENTRE (+0.5) so the curve spans whole
// cells edge-to-edge. Symmetric in (px - cx) and (py - cy), so the test -- and the
// outline built from it -- is exactly four-way symmetric about the box.
fn bool ellipse_in(int px, int py, float cx, float cy, float a, float b) {
    float dx = ((float)px + 0.5f - cx) / a;
    float dy = ((float)py + 0.5f - cy) / b;
    return dx * dx + dy * dy <= 1.0f;
}

// Rasterise the 1px outline of the ellipse inscribed in the box (x0,y0)-(x1,y1),
// in block-pixel coords. Roundness follows the box: a square drag gives a circle,
// a wide one an oval, and a bigger drag a smoother curve. When `commit`, write the
// pen into the tile data; otherwise draw a live preview cell. Interior untouched.
//
// A pixel is on the outline when it is inside the filled ellipse but at least one
// 4-neighbour is outside -- the inner boundary, which stays a connected 1px ring.
fn void circle_pixels(int x0, int y0, int x1, int y1, bool commit, float ox, float oy, float pxsz) {
    int xlo = x0 < x1 ? x0 : x1;
    int xhi = x0 < x1 ? x1 : x0;
    int ylo = y0 < y1 ? y0 : y1;
    int yhi = y0 < y1 ? y1 : y0;

    char    pen = (char)palette::selected_color();
    RLColor col = palette::tile_color((int)pen);

    int wpx = xhi - xlo;
    int hpx = yhi - ylo;

    // Degenerate box (zero width or height): the ellipse collapses to the line, so
    // just lay every cell of the box -- a 1px straight segment.
    if (wpx == 0 || hpx == 0) {
        for (int by = ylo; by <= yhi; by++) {
            for (int bx = xlo; bx <= xhi; bx++) {
                if (commit) {
                    int t = block_tile(bx / 8, by / 8);
                    if (t < tile_count) set_pixel(t, bx % 8, by % 8, pen);
                } else {
                    Rect r = { .x = ox + (float)bx * pxsz, .y = oy + (float)by * pxsz, .width = pxsz, .height = pxsz };
                    rl::draw_rectangle_rec(r, col);
                }
            }
        }
        return;
    }

    // Box spans pixels xlo..xhi inclusive: in continuous space that is the range
    // [xlo, xhi + 1], so the centre and semi-axes use the +1 full-cell extent. This
    // lets the ellipse touch all four edges regardless of even/odd box size.
    float cx = (float)(xlo + xhi + 1) * 0.5f;
    float cy = (float)(ylo + yhi + 1) * 0.5f;
    float a  = (float)(wpx + 1) * 0.5f;
    float b  = (float)(hpx + 1) * 0.5f;

    for (int by = ylo; by <= yhi; by++) {
        for (int bx = xlo; bx <= xhi; bx++) {
            if (!ellipse_in(bx, by, cx, cy, a, b)) continue;
            bool edge = !ellipse_in(bx - 1, by, cx, cy, a, b)
                     || !ellipse_in(bx + 1, by, cx, cy, a, b)
                     || !ellipse_in(bx, by - 1, cx, cy, a, b)
                     || !ellipse_in(bx, by + 1, cx, cy, a, b);
            if (!edge) continue;

            if (commit) {
                int t = block_tile(bx / 8, by / 8);
                if (t < tile_count) set_pixel(t, bx % 8, by % 8, pen);
            } else {
                Rect r = { .x = ox + (float)bx * pxsz, .y = oy + (float)by * pxsz, .width = pxsz, .height = pxsz };
                rl::draw_rectangle_rec(r, col);
            }
        }
    }
}

// The right Edit pane: the selection block (sel_dim x sel_dim tiles anchored at
// `sel`) enlarged, with a white outline. The block is clamped to the page's right
// edge so it never crosses the 16-wide wrap; cells past the file end stay blank.
fn void draw_editor(Rect area, int tool) {
    edit_hover = rl::check_collision_point_rec(rl::get_mouse_position(), area);

    if (data == null || sel >= tile_count) {
        rl::draw_rectangle_rec(area, BG);
        rl::draw_rectangle_lines_ex(area, ui::px(1), BORDER);
        return;
    }

    // The selection is always a full sel_dim x sel_dim square; it never clamps at
    // an edge (block_tile wraps instead), so the Edit pane is always square.
    int bw   = sel_dim;
    int bh   = sel_dim;
    int span = sel_dim;

    float side = area.width < area.height ? area.width : area.height;
    float cell = side / (float)span;
    float bwpx = cell * (float)bw;
    float bhpx = cell * (float)bh;
    float ox = area.x + (area.width  - bwpx) * 0.5f;
    float oy = area.y + (area.height - bhpx) * 0.5f;

    // Handle input first so freehand writes show this very frame.
    handle_edit_input(tool, ox, oy, cell, bw, bh);

    for (int dr = 0; dr < bh; dr++) {
        for (int dc = 0; dc < bw; dc++) {
            int t = block_tile(dc, dr);
            Rect c = { .x = ox + (float)dc * cell, .y = oy + (float)dr * cell, .width = cell, .height = cell };
            if (t < tile_count) {
                draw_tile(t, c);
            } else {
                rl::draw_rectangle_rec(c, BG);
            }
        }
    }

    // Live shape preview: the outline-to-be, drawn straight to the screen (no
    // memory copy), so it costs only the border cells.
    if (sq_active) {
        if (tool == TOOL_CIRCLE) {
            circle_pixels(sq_x0, sq_y0, sq_x1, sq_y1, false, ox, oy, cell / 8.0f);
        } else {
            square_pixels(sq_x0, sq_y0, sq_x1, sq_y1, false, ox, oy, cell / 8.0f);
        }
    }

    Rect r = { .x = ox, .y = oy, .width = bwpx, .height = bhpx };
    rl::draw_rectangle_lines_ex(r, ui::px(1), LINE);

    // Per-pixel grid drawn LAST so it sits on top of tiles and the live preview.
    if (show_grid) {
        float pxsz = cell / 8.0f;
        for (int k = 0; k <= bw * 8; k++) {
            float x = ox + (float)k * pxsz;
            rl::draw_line_ex({ x, oy }, { x, oy + bhpx }, ui::px(1), PXGRID);
        }
        for (int k = 0; k <= bh * 8; k++) {
            float y = oy + (float)k * pxsz;
            rl::draw_line_ex({ ox, y }, { ox + bwpx, y }, ui::px(1), PXGRID);
        }
    }

    float ppx   = cell / 8.0f;
    int   bwpix = bw * 8;
    int   bhpix = bh * 8;

    // Pixel selection: whiten each selected pixel (the exact shape) and mark the
    // shape's anchor (least-x / least-y cell) with an orange dot.
    if (psel_count > 0) {
        int axmin = bwpix;
        int aymin = bhpix;
        for (int y = 0; y < bhpix; y++) {
            for (int x = 0; x < bwpix; x++) {
                if (!psel_mask[y * PCLIP_SIDE + x]) continue;
                if (x < axmin) axmin = x;
                if (y < aymin) aymin = y;
                Rect pr = { .x = ox + (float)x * ppx, .y = oy + (float)y * ppx, .width = ppx, .height = ppx };
                rl::draw_rectangle_rec(pr, MSEL_FILL);
            }
        }
        float rad = ppx * 0.5f;
        rl::draw_circle_v({ ox + (float)axmin * ppx + rad, oy + (float)aymin * ppx + rad }, rad, ANCHOR);
    }

    // Paste preview: the clipboard SHAPE (translucent orange) re-anchored on the
    // cursor, so you can see exactly which pixels a Ctrl+V will land. Follows the
    // mouse; persists until the next copy.
    if (pclip_on && pcur_valid) {
        for (int py = 0; py < pclip_h; py++) {
            for (int px = 0; px < pclip_w; px++) {
                if (!pclip_mask[py * pclip_w + px]) continue;
                int bx = pcur_x + px;
                int by = pcur_y + py;
                if (bx < 0 || by < 0 || bx >= bwpix || by >= bhpix) continue;
                Rect pr = { .x = ox + (float)bx * ppx, .y = oy + (float)by * ppx, .width = ppx, .height = ppx };
                rl::draw_rectangle_rec(pr, PASTE_FILL);
            }
        }
    }
}
