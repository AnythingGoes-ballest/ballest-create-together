// The "create together" page in the Create menu (Window.DockInCreatePage: a label after "files" and "published"):
//   create together                                   [+ new session]
//   [ join with a code          ] [join]
//   (what's happening, or what happened last)          [cancel]  (while joining or starting)
//   open sessions                                      [refresh]
//     [ lowpoly city        obamanomicon      2/4   friends ]   a click joins
//   ...
// "+ new session" shows the form: start from a new map or one of your saved maps, who can join, how many players.

namespace Page
{

const float WIDTH = 1000;

UI::Window@ win;
int listView, formView;
UI::Button@ newButton, joinButton, cancelBusyButton, refreshButton;
UI::TextInput@ codeInput;
UI::Text@ statusText, listTitle;

// the list
array<int> cards;
array<string> cardIds;
double nextSearch = 0;
bool searching = false, searchedOnce = false;
string shownResults = "-";
bool shownBusy = false;

// the form
UI::Button@ fromNew, fromSaved, createButton, cancelButton;
UI::Dropdown@ mapChoice, whoChoice, maxChoice;
UI::Text@ whoHint, fromHint;
array<string> mapFiles;
bool fromSavedMap = false;
int view = -1;

const array<string> WHO_LABELS = {"public: everyone's list", "friends: your Steam friends", "code only: anyone with the code", "invite only: Steam invites"};
const array<string> WHO_HINTS = {
    "listed for everyone on the create together page; anyone can join, or use its code",
    "your Steam friends see it in their list; only your friends can join",
    "not listed: share the code (shown in the editor's together tab); only people with the code can join",
    "not listed and no code: invite friends from the editor's together tab; only your friends can join"};

Together::LobbyType TypeAt(int i)
{
    if (i == 0)
        return Together::Public;
    if (i == 1)
        return Together::Friends;
    if (i == 2)
        return Together::Code;
    return Together::InviteOnly;
}

int Clamp(int v, int lo, int hi) { return v < lo ? lo : (v > hi ? hi : v); }

void Build()
{
    @win = UI::CreateWindow();
    win.DockInCreatePage("create together");
    win.SetBackground(CARD_R, CARD_G, CARD_B, 0.97f);        // dark like the game's list rows on the light page
    win.SetCardBackground(BUTTON_R, BUTTON_G, BUTTON_B, 1);
    win.SetCornerRadius(6);
    win.SetPadding(22, 18);
    win.SetRowGap(10);
    win.StartHeader();
    win.AddText("create together", 30);
    win.AddSpace(0);
    @newButton = win.AddButton("+ new session");
    newButton.SetSize(220, 48);
    Primary(newButton);
    win.NewRow();
    @codeInput = win.AddTextInput(300, "session code", 18);
    codeInput.clearOnSubmit = false;
    @joinButton = win.AddButton("join");
    joinButton.SetSize(150, 44);
    Secondary(joinButton);
    win.NewRow();
    @statusText = win.AddText("", 15);
    statusText.SetWidth(WIDTH - 180);
    statusText.SetWrap(true);
    win.AddSpace(0);
    @cancelBusyButton = win.AddButton("cancel");
    cancelBusyButton.SetSize(130, 40);
    Secondary(cancelBusyButton);

    listView = win.StartView();
    win.SetScrolling(listView, true);
    BuildListHeader();

    formView = win.StartView();
    BuildForm();
    Show(listView);
}

void BuildListHeader()
{
    @listTitle = win.AddText("open sessions", 22);
    win.AddSpace(0);
    @refreshButton = win.AddButton("refresh");
    refreshButton.SetSize(130, 40);
    Secondary(refreshButton);
    win.NewRow();
}

void BuildForm()
{
    win.AddText("new session", 22);
    win.NewRow();
    Muted(win.AddText("start from", 15));
    win.NewRow();
    @fromNew = win.AddButton("a new map");
    fromNew.SetSize(220, 44);
    @fromSaved = win.AddButton("one of my maps");
    fromSaved.SetSize(300, 44);
    win.NewRow();
    @fromHint = win.AddText("", 14);
    Muted(fromHint);
    win.NewRow();
    @mapChoice = win.AddDropdown(560);
    Dark(mapChoice);
    win.NewRow();
    Muted(win.AddText("who can join", 15));
    win.NewRow();
    @whoChoice = win.AddDropdown(560);
    Dark(whoChoice);
    for (uint i = 0; i < WHO_LABELS.length(); i++)
        whoChoice.AddOption(WHO_LABELS[i]);
    whoChoice.selected = Clamp(parseInt(Storage::Get("who", "0")), 0, 3);
    win.NewRow();
    @whoHint = win.AddText("", 14);
    whoHint.SetWidth(WIDTH - 60);
    whoHint.SetWrap(true);
    Muted(whoHint);
    win.NewRow();
    Muted(win.AddText("players", 15));
    win.NewRow();
    @maxChoice = win.AddDropdown(200);
    Dark(maxChoice);
    for (int n = 2; n <= 8; n++)
        maxChoice.AddOption("" + n + " players");
    maxChoice.selected = Clamp(parseInt(Storage::Get("max", "2")), 0, 6);
    win.NewRow();
    @createButton = win.AddButton("start the session");
    createButton.SetSize(260, 50);
    Primary(createButton);
    @cancelButton = win.AddButton("cancel");
    cancelButton.SetSize(140, 50);
    Secondary(cancelButton);
}

void Show(int v)
{
    view = v;
    win.ShowView(v);
    if (v == formView)
        FillForm();
    else
        nextSearch = 0;
}

void FillForm()
{
    mapFiles = Together::SavedMaps();
    mapChoice.ClearOptions();
    for (uint i = 0; i < mapFiles.length(); i++)
        mapChoice.AddOption(MapTitle(mapFiles[i]));
    string last = Storage::Get("map", "");
    for (uint i = 0; i < mapFiles.length(); i++)
        if (mapFiles[i] == last)
            mapChoice.selected = int(i);
    fromSaved.label = mapFiles.length() > 0 ? "one of my maps" : "one of my maps (none saved yet)";
    fromSaved.SetTextColor(mapFiles.length() > 0 ? 1 : MUTED_R, mapFiles.length() > 0 ? 1 : MUTED_G, mapFiles.length() > 0 ? 1 : MUTED_B, 1);
    SetFrom(Storage::Get("from", "new") == "saved" && mapFiles.length() > 0);
}

void SetFrom(bool saved)
{
    fromSavedMap = saved;
    Chosen(fromNew, !saved);
    Chosen(fromSaved, saved);
    mapChoice.visible = saved;
    fromHint.text = saved ? "the session opens your map; only you can save it" : "the game asks you to name it first, then the session starts";
}

// --- the list ------------------------------------------------------------------------------------------------------

void Search()
{
    Together::FindLobbies();
    searching = true;
    nextSearch = Host::Time() + 6;
}

void ShowResults(bool force = false)
{
    int n = Together::FoundCount();
    bool busy = Session::Busy();
    string key = busy ? "b" : "";
    for (int i = 0; i < n; i++)
        key += Together::FoundId(i) + Together::FoundData(i, "map") + Together::FoundPlayers(i) + Together::FoundData(i, "ver") + "|";
    if (!searchedOnce)
        key = "-";
    if (key == shownResults && !force)
        return;
    shownResults = key;
    win.ClearView(listView);
    cards.resize(0);
    cardIds.resize(0);
    BuildListHeader();
    if (!searchedOnce)
    {
        Muted(win.AddText("looking for sessions...", 15));
        return;
    }
    int shown = 0;
    for (int i = 0; i < n; i++)
    {
        string ver = Together::FoundData(i, "vis") == "" ? "" : Together::FoundData(i, "ver");
        string vis = Together::FoundData(i, "vis");
        if (vis == "code" || vis == "invite")
            continue;                   // never listed: found by their code, or joined by a Steam invite
        bool otherVersion = ver != "" && ver != VERSION;
        bool full = Together::FoundPlayers(i) >= Together::FoundMaxPlayers(i) && Together::FoundMaxPlayers(i) > 0;
        bool can = !otherVersion && !full && !busy;
        int card = win.StartCard(can);
        UI::Text@ mapName = win.AddText(Shorten(Together::FoundData(i, "map"), 34), 20);
        mapName.SetWidth(430);
        UI::Text@ hostName = win.AddText(Shorten(Together::FoundData(i, "host"), 26), 16);
        hostName.SetWidth(300);
        Muted(hostName);
        UI::Text@ count = win.AddText("" + Together::FoundPlayers(i) + "/" + Together::FoundMaxPlayers(i), 16);
        count.SetWidth(80);
        UI::Text@ badge = win.AddText(otherVersion ? "needs version " + ver : (full ? "full" : (vis == "friends" ? "friends only" : (Together::FoundIsFriend(i) ? "public · friend" : "public"))), 14);
        if (otherVersion || full)
        {
            Bad(badge);
            Muted(mapName);
        }
        else
            Lime(badge);
        win.AddSpace(0);
        win.EndCard();
        if (can)
        {
            cards.insertLast(card);
            cardIds.insertLast(Together::FoundId(i));
        }
        shown++;
    }
    if (shown == 0)
    {
        win.NewRow();
        Muted(win.AddText("no open sessions right now: start one with + new session, or join one with its code", 15));
    }
}

string BusyText()
{
    switch (Session::phase)
    {
    case Session::CreatingLobby: return "starting...";
    case Session::OpeningEditor: return "starting...";
    case Session::FindingCode: return "finding...";
    case Session::JoiningLobby: return "joining...";
    case Session::Connecting: return "connecting...";
    }
    return "";
}

void Update()
{
    if (!win.IsTabOpen())
        return;
    bool busy = Session::Busy();
    if (Session::message != "")
    {
        statusText.text = Session::message;
        if (Session::messageBad)
            Bad(statusText);
        else
            Muted(statusText);
    }
    else
    {
        if (Together::Backend() == "none")
        {
            statusText.text = "Steam isn't running: sessions need Steam";
            Bad(statusText);
        }
        else
        {
            statusText.text = Together::Backend() == "test" ? "test copy: sessions are shared between this computer's test copies only" : "";
            Muted(statusText);
        }
    }
    joinButton.label = busy ? BusyText() : "join";
    refreshButton.label = searching ? "refreshing..." : "refresh";
    if (Session::phase == Session::FindingCode)
        searching = false;              // the session's code search owns the results now
    cancelBusyButton.visible = busy;
    newButton.visible = view == listView && !busy && Together::Backend() != "none";
    if (busy != shownBusy)
    {
        shownBusy = busy;
        ShowResults(true);              // cards can't be clicked while something is starting
    }

    // every click is read (and so used up) each frame: one made while busy doesn't fire later
    bool cancelClicked = cancelBusyButton.Clicked(), joinClicked = joinButton.Clicked(), submitted = codeInput.Submitted(),
         newClicked = newButton.Clicked(), refreshClicked = refreshButton.Clicked();
    if (cancelClicked)
        Session::Leave();
    if (!busy && (joinClicked || submitted))
    {
        Session::message = "";
        Session::JoinByCode(codeInput.text != "" ? codeInput.text : codeInput.typed);
    }
    if (newClicked && !busy)
    {
        Session::message = "";
        Show(formView);
    }

    if (view == listView)
    {
        if ((refreshClicked || Host::Time() >= nextSearch) && !busy && !searching)
            Search();
        if (searching && !Together::Searching())
        {
            searching = false;
            searchedOnce = true;
            ShowResults();
        }
        for (uint i = 0; i < cards.length(); i++)
            if (win.CardClicked(cards[i]))
            {
                Session::message = "";
                Session::JoinById(cardIds[i]);
            }
    }
    else if (view == formView)
    {
        if (Session::InSession())
            Show(listView);             // the session started: the form is done
        if (cancelButton.Clicked())
        {
            if (busy)
                Session::Leave();       // the start is cancelled, not just hidden
            Show(listView);
        }
        if (fromNew.Clicked())
            SetFrom(false);
        if (fromSaved.Clicked() && mapFiles.length() > 0)
            SetFrom(true);
        whoHint.text = WHO_HINTS[uint(Clamp(whoChoice.selected, 0, 3))];
        createButton.label = busy ? BusyText() : "start the session";
        bool createClicked = createButton.Clicked();
        if (createClicked && !busy)
        {
            int who = Clamp(whoChoice.selected, 0, 3), most = Clamp(maxChoice.selected, 0, 6);
            string file = fromSavedMap && mapChoice.selected >= 0 && uint(mapChoice.selected) < mapFiles.length() ? mapFiles[mapChoice.selected] : "";
            Storage::Set("from", fromSavedMap ? "saved" : "new");
            if (file != "")
                Storage::Set("map", file);
            Storage::Set("who", "" + who);
            Storage::Set("max", "" + most);
            Session::StartHosting(TypeAt(who), most + 2, file);
        }
    }
}

}  // namespace Page
