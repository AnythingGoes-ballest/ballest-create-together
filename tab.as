// In the editor during a session: a "together" tab in the left panel (Window.DockInEditorTab) and a small badge at
// the top of the screen, so everyone always sees that they're in a session and its code.
//   together
//   code  K7QX2M                (what friends type on the create together page)
//   public · 3 of 4 players
//     obamanomicon (host)
//     friend one
//   [invite friends]            (Steam's own invite dialog: hosts only)
//   [leave session]

namespace Tab
{

UI::Window@ win, badge;
UI::Text@ codeText, whoText, playersText, badgeText, noteText;   // playersText: unused spare row
UI::Button@ inviteButton, leaveButton;
string shownPlayers = "-";
int playersView;

void Build()
{
    @win = UI::CreateWindow();
    win.DockInEditorTab(Plugins::Folder() + "tab.png");
    win.SetBackground(0, 0, 0, 0);
    win.SetCardBackground(CARD_R, CARD_G, CARD_B, 1);
    win.StartHeader();
    win.AddText("together", 26);
    win.NewRow();
    Muted(win.AddText("code", 15));
    @codeText = win.AddText("", 30);
    Lime(codeText);
    win.NewRow();
    @whoText = win.AddText("", 15);
    Muted(whoText);
    win.NewRow();
    @playersText = win.AddText("", 15);
    win.NewRow();
    @inviteButton = win.AddButton("invite friends");
    inviteButton.SetSize(300, 44);
    Primary(inviteButton);
    win.NewRow();
    @leaveButton = win.AddButton("leave session");
    leaveButton.SetSize(300, 44);
    Secondary(leaveButton);
    win.NewRow();
    @noteText = win.AddText("", 13);
    noteText.SetWidth(320);
    noteText.SetWrap(true);
    Muted(noteText);
    win.NewRow();
    Muted(win.AddText("players", 15));
    playersView = win.StartView();      // last: ClearView empties only the players
    win.ShowView(playersView);
    win.visible = false;

    @badge = UI::CreateWindow();
    badge.SetAnchor(0.5f, 0);
    badge.SetPivot(0.5f, 0);
    badge.SetOffset(0, 44);
    badge.SetBackground(CARD_R, CARD_G, CARD_B, 0.92f);
    badge.SetCornerRadius(10);
    badge.SetPadding(14, 6);
    @badgeText = badge.AddText("", 15);
    badge.visible = false;
}

void ShowPlayers()
{
    array<string>@ names = Together::LobbyMembers();
    string key = "";
    for (uint i = 0; i < names.length(); i++)
        key += names[i] + "|";
    if (key == shownPlayers)
        return;
    shownPlayers = key;
    win.ClearView(playersView);
    for (uint i = 0; i < names.length(); i++)
    {
        UI::Text@ t = win.AddText((i == 0 ? "★ " : "  ") + Shorten(names[i], 28) + (i == 0 ? "  (host)" : ""), 16);
        if (i == 0)
            Lime(t);
        win.NewRow();
    }
}

void Update()
{
    bool on = Session::InSession() && Editor::IsOpen();
    win.visible = on;
    badge.visible = on && !Editor::IsTesting();
    if (!on)
        return;
    string code = Session::Code();
    bool host = Session::phase == Session::Hosting;
    string vis = Together::LobbyData("vis");
    int players = Together::Players(), most = Together::LobbyMaxPlayers();
    codeText.text = vis == "invite" ? "invite only" : code;
    whoText.text = (vis == "" ? "" : vis + " · ") + players + (most > 0 ? " of " + most : "") + " players";
    badgeText.text = "together · " + (vis == "invite" ? "invite only" : code) + " · " + players + (players == 1 ? " player" : " players") +
                     (host ? "" : " · " + Shorten(Together::LobbyData("host"), 18) + "'s map");
    inviteButton.visible = Together::Backend() == "steam";
    noteText.text = host ? "you're the host: the map is yours, only you can save it. When you leave, the session ends for everyone."
                         : "the map is " + Together::LobbyData("host") + "'s: only they can save or publish it.";
    if (win.IsTabOpen())
        ShowPlayers();
    if (inviteButton.Clicked() && !Together::InviteDialog())
        Session::Say("Steam's invite dialog isn't available here", true);
    if (leaveButton.Clicked())
        Session::Leave();
}

}  // namespace Tab
