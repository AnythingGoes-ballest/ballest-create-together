// In the editor during a session: a "together" tab in the left panel (Window.DockInEditorTab) and a small badge at
// the top of the screen, so everyone always sees that they're in a session and its code.
//   together
//   code  [K7QX2M4P]            (selectable: friends type it on the create together page)
//   public · 3 of 4 players
//   players
//     ★ obamanomicon (host)
//       friend one (you)
//   [invite friends]            (Steam's own invite dialog)
//   [leave session]             (the host: click twice, it ends the session for everyone)
//   (a note on who owns the map, and the last message)
// Plus the notice window: whatever ended or was refused (the host left, a save refused...), wherever the player is.

namespace Tab
{

UI::Window@ win, badge, noticeWin;
UI::Text@ whoText, badgeText, noteText, statusText, noticeText, codeLabel;
UI::TextInput@ codeBox;
UI::Button@ inviteButton, leaveButton, noticeOk, noticeJoin, copyButton;
double copyFlashEnd = 0;
string shownPlayers = "-", shownCode = "-";
int playersView;
double confirmUntil = 0;

void Build()
{
    @win = UI::CreateWindow();
    win.DockInEditorTab(Plugins::Folder() + "tab.png");
    win.SetBackground(0, 0, 0, 0);
    win.SetCardBackground(CARD_R, CARD_G, CARD_B, 1);
    win.StartHeader();
    win.AddText("together", 26);
    win.NewRow();
    @codeLabel = win.AddText("code", 15);
    Muted(codeLabel);
    @codeBox = win.AddTextInput(150, "", 20);
    codeBox.readOnly = true;
    codeBox.clearOnSubmit = false;
    @copyButton = win.AddButton("copy");     // the code on the clipboard, to paste to friends
    copyButton.SetSize(76, 36);
    Secondary(copyButton);
    win.NewRow();
    @whoText = win.AddText("", 15);
    Muted(whoText);
    win.NewRow();
    Muted(win.AddText("players", 15));
    playersView = win.StartView();      // the players: rebuilt when they change
    win.ShowView(playersView);          // the players, then the session's buttons and notes (ShowPlayers)
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

    @noticeWin = UI::CreateWindow();
    noticeWin.SetAnchor(0.5f, 0.42f);
    noticeWin.SetPivot(0.5f, 0.5f);
    noticeWin.SetBackground(CARD_R, CARD_G, CARD_B, 0.97f);
    noticeWin.SetCornerRadius(10);
    noticeWin.SetPadding(24, 18);
    noticeWin.SetBlocksClicks(true);
    noticeWin.zOrder = 600;             // over the plugin's own windows and the menus
    Lime(noticeWin.AddText("create together", 20));
    noticeWin.NewRow();
    @noticeText = noticeWin.AddText("", 16);
    noticeText.SetWidth(460);
    noticeText.SetWrap(true);
    noticeWin.NewRow();
    noticeWin.AddSpace(0);
    @noticeJoin = noticeWin.AddButton("join now");
    noticeJoin.SetSize(150, 42);
    Primary(noticeJoin);
    @noticeOk = noticeWin.AddButton("ok");
    noticeOk.SetSize(110, 42);
    Secondary(noticeOk);
    noticeWin.visible = false;
}

void ShowPlayers()
{
    array<string>@ names = Together::LobbyMembers();
    array<string>@ ids = Together::LobbyMemberIds();
    string own = Together::OwnId(), owner = Together::LobbyOwnerId();
    string key = "";
    for (uint i = 0; i < names.length(); i++)
        key += names[i] + (i < ids.length() ? ids[i] : "") + "|";
    if (key == shownPlayers)
        return;
    shownPlayers = key;
    win.ClearView(playersView);
    confirmUntil = 0;                   // the button is made again: a first click doesn't carry over
    for (uint i = 0; i < names.length(); i++)
    {
        bool isHost = i < ids.length() && ids[i] == owner, isYou = i < ids.length() && ids[i] == own;
        UI::Text@ t = win.AddText((isHost ? "★ " : "   ") + Shorten(names[i], 18) + (isYou ? "  (you)" : ""), 16);
        if (isHost)
            Lime(t);
        win.NewRow();
    }
    // the session's buttons and notes come after the players (in the same view, rebuilt with them)
    win.NewRow();
    @inviteButton = win.AddButton("invite friends");
    inviteButton.SetSize(300, 44);
    Primary(inviteButton);
    win.NewRow();
    @leaveButton = win.AddButton(Session::phase == Session::Hosting ? "end the session" : "leave the session");
    leaveButton.SetSize(300, 44);
    Secondary(leaveButton);
    win.NewRow();
    @noteText = win.AddText("", 13);
    noteText.SetWidth(320);
    noteText.SetWrap(true);
    Muted(noteText);
    win.NewRow();
    @statusText = win.AddText("", 13);
    statusText.SetWidth(320);
    statusText.SetWrap(true);
}

void ShowNotice()
{
    bool any = Session::notices.length() > 0;
    if (any)
        noticeText.text = Session::notices[0] + (Session::notices.length() > 1 ? "  (" + Session::notices.length() + ")" : "");
    noticeWin.visible = any;
    bool onInvite = false;
    if (any && Session::pendingInvite != "")
        onInvite = Session::notices[0] == Session::inviteNotice;
    noticeJoin.visible = onInvite;
    bool ok = noticeOk.Clicked(), join = noticeJoin.Clicked();
    if (any && (ok || join))
        Session::notices.removeAt(0);
    if (join && noticeJoin.visible)
        Session::JoinInvite(Session::pendingInvite);
    else if (ok && onInvite)
    {
        Session::pendingInvite = "";    // "ok" on the invite turns it down
        Session::inviteNotice = "";
    }
}

void Update()
{
    ShowNotice();
    bool on = Session::InSession() && Editor::IsOpen();
    win.visible = on;
    badge.visible = on && !Editor::IsTesting();
    if (!on)
    {
        shownPlayers = "-";
        return;
    }
    if (Session::openTab)
    {
        Session::openTab = false;
        win.OpenTab();
    }
    bool host = Session::phase == Session::Hosting;
    string vis = Together::LobbyData("vis");
    string code = host ? Session::Code() : "";
    // a joiner sees the code only if it's one they can share: a public session's or a code-only one they used
    if (!host && (vis == "public" || vis == "code"))
        code = Session::joinCode;
    if (code + "|" + vis != shownCode)
    {
        shownCode = code + "|" + vis;
        codeBox.value = code;
        codeBox.visible = code != "";
        copyButton.visible = code != "";
        codeLabel.visible = code != "";     // without a code, the line below says what kind of session it is
        codeLabel.text = "code";
    }
    // the same count as the names below it (the lobby's members)
    array<string>@ members = Together::LobbyMembers();
    int most = Together::LobbyMaxPlayers();
    int players = 0;
    for (uint i = 0; i < members.length(); i++)
        players++;
    if (players == 0)
        players = Together::Players();
    string kind = vis == "code" ? "code only" : (vis == "invite" ? "invite only" : (vis == "friends" ? "friends only" : (vis == "public" ? "public" : "")));
    whoText.text = (kind == "" ? "" : kind + " · ") + players + (most > 0 ? " of " + most : "") + " players";
    // the code stays in the tab: the badge is on screen (and on streams), so a code-only session's code isn't on it
    badgeText.text = (code != "" && vis != "code" ? "session " + code : "session") + " · " + players + (players == 1 ? " player" : " players") +
                     (host ? " · you're the host" : " · hosted by " + Shorten(Session::HostName(), 24));
    ShowPlayers();
    string shown = code;            // (TextInput.value can only be set)
    if (copyButton.Clicked() && shown != "")
    {
        if (Host::SetClipboard(shown))
            copyFlashEnd = Host::Time() + 2;
        else
            Session::Say("couldn't copy the code: select it and press Ctrl+C", true);
    }
    string copyLabel = "copy";
    if (Host::Time() < copyFlashEnd)
        copyLabel = "copied";
    copyButton.label = copyLabel;
    if (inviteButton is null)
        return;
    // the host's invites are let in whatever the kind (they're the host's friends); a joiner's only where anyone may join
    inviteButton.visible = Together::Backend() == "steam" && (host || vis == "public");
    noteText.text = host ? "you're the host: the map is yours and only you can save it (save often). Ending the session sends everyone back to the menu."
                         : "the map is " + Session::HostName() + "'s: only they can save or publish it. Your undo and redo are your own.";
    if (confirmUntil > 0)
    {
        statusText.text = "this ends the session for everyone; unsaved changes are lost";
        Bad(statusText);
    }
    else
    {
        statusText.text = Session::message;
        if (Session::messageBad)
            Bad(statusText);
        else
            Muted(statusText);
    }
    if (inviteButton.Clicked() && !Together::InviteDialog())
        Session::Say("Steam's invite dialog isn't available here", true);
    if (host && confirmUntil > 0 && Host::Time() > confirmUntil)
    {
        confirmUntil = 0;
        leaveButton.label = "end the session";
    }
    if (leaveButton.Clicked())
    {
        if (host && confirmUntil == 0)
        {
            confirmUntil = Host::Time() + 4;
            leaveButton.label = "click again to end";
        }
        else
        {
            confirmUntil = 0;
            Session::Leave();
        }
    }
}

}  // namespace Tab
