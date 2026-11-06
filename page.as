// The "create together" page in the Create menu (Window.DockInCreatePage: a label after "files" and "published"):
//   create together                                   [+ new session]
//   [ join with a code          ] [join]
//   (what happened last)
//   open sessions                                      [refresh]
//     [ lowpoly city        obamanomicon      2/4   friend ]   a click joins
//   ...
// "+ new session" shows the form: start from a new map or one of your saved maps, who can join, how many players.

namespace Page
{

const float WIDTH = 1000;

UI::Window@ win;
int listView, formView;
UI::Button@ newButton, joinButton, refreshButton, backButton;
UI::TextInput@ codeInput;
UI::Text@ statusText, listTitle;

// the list
array<int> cards;
array<string> cardIds;
double nextSearch = 0;
bool searching = false;
string shownResults = "-";

// the form
UI::Button@ fromNew, fromSaved, createButton, cancelButton;
UI::Dropdown@ mapChoice, whoChoice, maxChoice;
UI::Text@ whoHint;
array<string> mapFiles;
bool fromSavedMap = false;
int view = -1;

const array<string> WHO_LABELS = {"public: everyone's list", "friends: your Steam friends", "code only: anyone with the code", "invite only: Steam invites"};
const array<string> WHO_HINTS = {
    "listed for everyone on the create together page",
    "your Steam friends see it in their list",
    "not listed: share the code to let people in",
    "not listed and no code: invite friends through Steam from the editor"};

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
    @codeInput = win.AddTextInput(300, "join with a code", 18);
    codeInput.clearOnSubmit = false;
    @joinButton = win.AddButton("join");
    joinButton.SetSize(110, 44);
    Secondary(joinButton);
    win.NewRow();
    @statusText = win.AddText("", 15);
    statusText.SetWidth(WIDTH);
    statusText.SetWrap(true);

    listView = win.StartView();
    @listTitle = win.AddText("open sessions", 22);
    win.AddSpace(0);
    @refreshButton = win.AddButton("refresh");
    refreshButton.SetSize(130, 40);
    Secondary(refreshButton);
    win.NewRow();

    formView = win.StartView();
    BuildForm();
    Show(listView);
}

void BuildForm()
{
    win.AddText("new session", 22);
    win.AddSpace(0);
    @backButton = win.AddButton("back");
    backButton.SetSize(110, 40);
    Secondary(backButton);
    win.NewRow();
    Muted(win.AddText("start from", 15));
    win.NewRow();
    @fromNew = win.AddButton("a new map");
    fromNew.SetSize(220, 44);
    @fromSaved = win.AddButton("one of my maps");
    fromSaved.SetSize(220, 44);
    win.NewRow();
    @mapChoice = win.AddDropdown(560);
    win.NewRow();
    Muted(win.AddText("who can join", 15));
    win.NewRow();
    @whoChoice = win.AddDropdown(560);
    for (uint i = 0; i < WHO_LABELS.length(); i++)
        whoChoice.AddOption(WHO_LABELS[i]);
    whoChoice.selected = parseInt(Storage::Get("who", "0"));
    win.NewRow();
    @whoHint = win.AddText("", 14);
    Muted(whoHint);
    win.NewRow();
    Muted(win.AddText("players", 15));
    win.NewRow();
    @maxChoice = win.AddDropdown(200);
    for (int n = 2; n <= 8; n++)
        maxChoice.AddOption("" + n + " players");
    maxChoice.selected = parseInt(Storage::Get("max", "2"));
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
    newButton.visible = v == listView;
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
    SetFrom(Storage::Get("from", "new") == "saved" && mapFiles.length() > 0);
}

void SetFrom(bool saved)
{
    fromSavedMap = saved;
    Chosen(fromNew, !saved);
    Chosen(fromSaved, saved);
    mapChoice.visible = saved;
}

// --- the list ------------------------------------------------------------------------------------------------------

void Search()
{
    Together::FindLobbies();
    searching = true;
    nextSearch = Host::Time() + 6;
}

void ShowResults()
{
    int n = Together::FoundCount();
    string key;
    for (int i = 0; i < n; i++)
        key += Together::FoundId(i) + Together::FoundData(i, "map") + Together::FoundPlayers(i) + "|";
    if (key == shownResults)
        return;
    shownResults = key;
    win.ClearView(listView);
    cards.resize(0);
    cardIds.resize(0);
    @listTitle = win.AddText("open sessions", 22);
    win.AddSpace(0);
    @refreshButton = win.AddButton("refresh");
    refreshButton.SetSize(130, 40);
    Secondary(refreshButton);
    win.NewRow();
    int shown = 0;
    for (int i = 0; i < n; i++)
    {
        if (Together::FoundData(i, "ver") != VERSION && Together::FoundData(i, "ver") != "")
            continue;               // another version of the plugin: can't join it
        int card = win.StartCard(true);
        UI::Text@ mapName = win.AddText(Shorten(Together::FoundData(i, "map"), 34), 20);
        mapName.SetWidth(430);
        UI::Text@ hostName = win.AddText(Shorten(Together::FoundData(i, "host"), 26), 16);
        hostName.SetWidth(300);
        Muted(hostName);
        UI::Text@ count = win.AddText("" + Together::FoundPlayers(i) + "/" + Together::FoundMaxPlayers(i), 16);
        count.SetWidth(80);
        bool full = Together::FoundPlayers(i) >= Together::FoundMaxPlayers(i) && Together::FoundMaxPlayers(i) > 0;
        UI::Text@ badge = win.AddText(full ? "full" : (Together::FoundIsFriend(i) ? "friend" : "public"), 14);
        if (full)
            Bad(badge);
        else
            Lime(badge);
        win.AddSpace(0);
        win.EndCard();
        cards.insertLast(card);
        cardIds.insertLast(Together::FoundId(i));
        shown++;
    }
    if (shown == 0)
    {
        win.NewRow();
        Muted(win.AddText("no open sessions right now: start one with + new session, or join one with its code", 15));
    }
}

void Update()
{
    if (!win.IsTabOpen())
        return;
    if (Session::message != "")
    {
        statusText.text = Session::message;
        if (Session::messageBad)
            Bad(statusText);
        else
            Muted(statusText);
    }
    else
        statusText.text = Together::Backend() == "test" ? "test copy: sessions are shared between this computer's test copies only" : "";
    bool busy = Session::Busy();
    joinButton.visible = !busy;
    newButton.visible = view == listView && !busy;

    if (joinButton.Clicked() || codeInput.Submitted())
        Session::JoinByCode(codeInput.text != "" ? codeInput.text : codeInput.typed);
    if (newButton.Clicked())
        Show(formView);

    if (view == listView)
    {
        if (refreshButton.Clicked() || Host::Time() >= nextSearch)
            Search();
        if (searching && !Together::Searching())
        {
            searching = false;
            ShowResults();
        }
        for (uint i = 0; i < cards.length(); i++)
            if (win.CardClicked(cards[i]))
                Session::JoinById(cardIds[i]);
    }
    else if (view == formView)
    {
        if (backButton.Clicked() || cancelButton.Clicked())
            Show(listView);
        if (fromNew.Clicked())
            SetFrom(false);
        if (fromSaved.Clicked() && mapFiles.length() > 0)
            SetFrom(true);
        whoHint.text = WHO_HINTS[uint(whoChoice.selected) < WHO_HINTS.length() ? whoChoice.selected : 0];
        createButton.visible = !busy;
        if (createButton.Clicked())
        {
            string file = fromSavedMap && mapChoice.selected >= 0 && uint(mapChoice.selected) < mapFiles.length() ? mapFiles[mapChoice.selected] : "";
            Storage::Set("from", fromSavedMap ? "saved" : "new");
            if (file != "")
                Storage::Set("map", file);
            Storage::Set("who", "" + whoChoice.selected);
            Storage::Set("max", "" + maxChoice.selected);
            Session::StartHosting(TypeAt(whoChoice.selected), maxChoice.selected + 2, file);
        }
    }
}

}  // namespace Page
