// Native "open file" dialog.
//
// We deliberately avoid any one desktop's API: we shell out to whichever generic
// file-picker helper is installed, preferring the running desktop's own (kdialog
// on KDE) and otherwise falling back through zenity / qarma / matedialog. The
// chosen path is read back from the helper's stdout.
module yate::dialog;

extern fn void* popen(ZString cmd, ZString mode) @cname("popen");
extern fn int   pclose(void* stream) @cname("pclose");
extern fn char* fgets(char* buf, int n, void* stream) @cname("fgets");
extern fn int   setenv(ZString name, ZString value, int overwrite) @cname("setenv");

const ZString OPEN_CMD = `sh -c 'case "${XDG_CURRENT_DESKTOP:-}" in *KDE*) command -v kdialog >/dev/null 2>&1 && exec kdialog --getopenfilename "$HOME";; esac; command -v zenity >/dev/null 2>&1 && exec zenity --file-selection; command -v kdialog >/dev/null 2>&1 && exec kdialog --getopenfilename "$HOME"; command -v qarma >/dev/null 2>&1 && exec qarma --file-selection; command -v matedialog >/dev/null 2>&1 && exec matedialog --file-selection' 2>/dev/null`;

const ZString SAVE_CMD = `sh -c 'case "${XDG_CURRENT_DESKTOP:-}" in *KDE*) command -v kdialog >/dev/null 2>&1 && exec kdialog --getsavefilename "$HOME";; esac; command -v zenity >/dev/null 2>&1 && exec zenity --file-selection --save --confirm-overwrite; command -v kdialog >/dev/null 2>&1 && exec kdialog --getsavefilename "$HOME"; command -v qarma >/dev/null 2>&1 && exec qarma --file-selection --save --confirm-overwrite; command -v matedialog >/dev/null 2>&1 && exec matedialog --file-selection --save --confirm-overwrite' 2>/dev/null`;

// As SAVE_CMD, but pre-fills the dialog with $YATE_SUGGEST. Passing the suggestion
// through the environment (not the command text) sidesteps shell quoting/injection.
const ZString SAVE_NAMED_CMD = `sh -c 'case "${XDG_CURRENT_DESKTOP:-}" in *KDE*) command -v kdialog >/dev/null 2>&1 && exec kdialog --getsavefilename "$YATE_SUGGEST";; esac; command -v zenity >/dev/null 2>&1 && exec zenity --file-selection --save --confirm-overwrite --filename="$YATE_SUGGEST"; command -v kdialog >/dev/null 2>&1 && exec kdialog --getsavefilename "$YATE_SUGGEST"; command -v qarma >/dev/null 2>&1 && exec qarma --file-selection --save --confirm-overwrite --filename="$YATE_SUGGEST"; command -v matedialog >/dev/null 2>&1 && exec matedialog --file-selection --save --confirm-overwrite --filename="$YATE_SUGGEST"' 2>/dev/null`;

// Run a picker helper and write the chosen path into `out` (NUL-terminated).
// Returns false if the helper is missing, the dialog was cancelled, or no path
// came back.
fn bool run(ZString cmd, char* out, usz cap) {
    void* pipe = popen(cmd, "r");
    if (pipe == null) return false;

    char* got = fgets(out, (int)cap, pipe);
    pclose(pipe);
    if (got == null) return false;

    // Strip the trailing newline the helper prints after the path.
    usz n = 0;
    while (out[n] != 0) n++;
    while (n > 0 && (out[n - 1] == '\n' || out[n - 1] == '\r')) {
        out[n - 1] = 0;
        n--;
    }
    return n > 0;
}

// Native "open" dialog: pick an existing file to read.
fn bool pick_file(char* out, usz cap) => run(OPEN_CMD, out, cap);

// Native "save" dialog: pick a path to create/overwrite.
fn bool pick_save_file(char* out, usz cap) => run(SAVE_CMD, out, cap);

// Native "save" dialog pre-filled with `suggest` as the default filename. The user
// is free to change or replace it before confirming.
fn bool pick_save_file_named(ZString suggest, char* out, usz cap) {
    setenv("YATE_SUGGEST", suggest, 1);
    return run(SAVE_NAMED_CMD, out, cap);
}
