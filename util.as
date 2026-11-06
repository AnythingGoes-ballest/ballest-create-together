// Small helpers and the colours the windows share (the game's widget colours are linear: each is the linear value
// of the colour in its comment).

const float CARD_R = 0.0116f, CARD_G = 0.0137f, CARD_B = 0.0194f;           // #1c1f26
const float BUTTON_R = 0.0232f, BUTTON_G = 0.0273f, BUTTON_B = 0.0382f;     // #2a2e37
const float PRIMARY_R = 0.0782f, PRIMARY_G = 0.2051f, PRIMARY_B = 0.0048f;  // #4f7d0f
const float LIME_R = 0.5647f, LIME_G = 0.9047f, LIME_B = 0.0319f;           // #c6f432
const float MUTED_R = 0.2582f, MUTED_G = 0.2747f, MUTED_B = 0.3185f;        // #8b8f99
const float BLUE_R = 0.0284f, BLUE_G = 0.1590f, BLUE_B = 0.4342f;           // #2f6fb0
const float BAD_R = 1.0f, BAD_G = 0.1714f, BAD_B = 0.147f;                  // #ff736b
const float SELECTED_R = 0.0402f, SELECTED_G = 0.1046f, SELECTED_B = 0.0037f; // #385a0a

void Muted(UI::Text@ t) { t.SetColor(MUTED_R, MUTED_G, MUTED_B, 1); }
void Lime(UI::Text@ t) { t.SetColor(LIME_R, LIME_G, LIME_B, 1); }
void Bad(UI::Text@ t) { t.SetColor(BAD_R, BAD_G, BAD_B, 1); }
void Primary(UI::Button@ b) { b.SetBackground(PRIMARY_R, PRIMARY_G, PRIMARY_B, 1); }
void Secondary(UI::Button@ b) { b.SetBackground(BUTTON_R, BUTTON_G, BUTTON_B, 1); }
void Chosen(UI::Button@ b, bool on) { b.SetBackground(on ? SELECTED_R : BUTTON_R, on ? SELECTED_G : BUTTON_G, on ? SELECTED_B : BUTTON_B, 1); }

string Trim(const string &in text)
{
    int a = 0, b = int(text.length()) - 1;
    while (a <= b && (text[a] == 32 || text[a] == 9 || text[a] == 10 || text[a] == 13))
        a++;
    while (b >= a && (text[b] == 32 || text[b] == 9 || text[b] == 10 || text[b] == 13))
        b--;
    return text.substr(a, b - a + 1);
}

string Upper(const string &in text)
{
    string t = text;
    for (uint i = 0; i < t.length(); i++)
        if (t[i] >= 97 && t[i] <= 122)
            t[i] = t[i] - 32;
    return t;
}

// A lobby's code: six letters and digits that can't be mixed up (no 0/O, 1/I), made from the lobby's id so every
// player who sees the lobby sees the same code.
const string CODE_LETTERS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
string CodeFor(const string &in id)
{
    uint h = 2166136261;
    for (uint i = 0; i < id.length(); i++)
    {
        h ^= id[i];
        h *= 16777619;
    }
    string code;
    for (int i = 0; i < 6; i++)
    {
        code += CODE_LETTERS.substr(h % 32, 1);
        h = h / 32 + (h % 7) * 99991 + uint(i) * 131;
    }
    return code;
}

// What a typed code becomes: upper case, spaces and dashes left out.
string CleanCode(const string &in typed)
{
    string t = Upper(Trim(typed)), res;
    for (uint i = 0; i < t.length(); i++)
        if (t[i] != 32 && t[i] != 45)
            res += t.substr(i, 1);
    return res;
}

// A saved map's file name (Map_LevelEditorMain&<display name>_<creator>.balledit) as the files list shows it.
string MapTitle(const string &in file)
{
    int amp = file.findLast("&");
    string name = amp < 0 ? file : file.substr(amp + 1);
    int dot = name.findLast(".balledit");
    if (dot >= 0)
        name = name.substr(0, dot);
    int under = name.findLast("_");
    if (under > 0)
        name = name.substr(0, under);
    return name;
}

string Shorten(const string &in text, uint most)
{
    return text.length() <= most ? text : text.substr(0, most - 1) + "…";
}
