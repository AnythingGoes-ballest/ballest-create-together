// The session: hosting one (a lobby, then the editor opened as a listen server) or joining one (the lobby, then the
// editor over the network). The editor's own replication does the editing; this only gets everyone into the same
// editor and keeps the lobby saying where it is. Who may stay in the editor is the host DLL's call (Together::):
// public sessions, any lobby member; friends and invite only, the host's Steam friends; code only, members who proved
// the code.
//
// The lobby's data, read by everyone who lists it:
//   ct=1 (the plugin's own tag), map, host (the host's name), ver (this plugin's version: other versions can't join),
//   vis (public / friends / code / invite), ch (a lookup key made from the code: never the code itself), and addr
//   (where the editor is, set only once the editor listens; a joiner checks it is the lobby owner's).

const string VERSION = "0.1.0";

namespace Session
{

enum Phase
{
    Idle,
    CreatingLobby,      // hosting: the lobby is being made
    OpeningEditor,      // hosting: the editor is opening as a listen server (a new map is named first)
    Hosting,
    FindingCode,        // joining by code: looking for the lobby
    JoiningLobby,
    Connecting,         // joining: the editor is loading from the host
    Joined
}

Phase phase = Idle;
string message;                 // what happened last, for the page ("" for nothing)
bool messageBad = false;
double messageAt = 0;
array<string> notices;          // what the player must see wherever they are (the notice window), oldest first
string pendingInvite;           // an invite that came while the player was editing a map of their own, or hosting
string inviteNotice;            // the notice that offers it ("join now" shows on that one only)
string joinAfter;               // an invite to join once the player is back on the menu (after leaving a session)
bool hostSaid = false;          // the host (DLL) already told the player why their session is over
double phaseSince = 0;
double endingSince = -1;        // the session looked over at this time (it must stay so for a moment)
bool openTab = false;           // the editor's together tab opens once, when a session starts
bool joinable = true;           // what the host last told Steam (a full session takes nobody new)

// the session being started
Together::LobbyType startType = Together::Public;
int startMax = 4;
string startMap;                // a saved map's file, or "" for a new map
string sessionCode;             // the host's: shown to the host, its lookup key in the lobby
string joinCode;
string joinId;
array<string> candidates;       // joining by code: the sessions whose lookup key matches, still to try

void Set(Phase p)
{
    if (p == Hosting || p == JoiningLobby || p == CreatingLobby)
        hostSaid = false;
    phase = p;
    phaseSince = Host::Time();
    endingSince = -1;
}

void Say(const string &in text, bool bad = false)
{
    message = text;
    messageBad = bad;
    messageAt = Host::Time();
    if (text != "")
        Log::Info(text);
}

void Notify(const string &in text)
{
    if (text == "" || (notices.length() > 0 && notices[notices.length() - 1] == text))
        return;
    if (notices.length() >= 4)
        notices.removeAt(0);
    notices.insertLast(text);
    Log::Info("notice: " + text);
}

bool Busy() { return phase != Idle && phase != Hosting && phase != Joined; }
bool InSession() { return phase == Hosting || phase == Joined; }
bool CanHaveCode(Together::LobbyType t) { return t == Together::Public || t == Together::Code; }

string VisibilityName(Together::LobbyType t)
{
    if (t == Together::Public)
        return "public";
    if (t == Together::Friends)
        return "friends";
    if (t == Together::Code)
        return "code";
    return "invite";
}

// A new code: from the host's system random source (Together::NewSessionCode), nothing anyone could work out.
string NewCode() { return Together::NewSessionCode(); }

// --- starting ------------------------------------------------------------------------------------------------------

void StartHosting(Together::LobbyType type, int maxPlayers, const string &in mapFile)
{
    if (Busy() || InSession())
        return;
    pendingInvite = "";
    inviteNotice = "";
    joinAfter = "";
    startType = type;
    startMax = maxPlayers;
    startMap = mapFile;
    sessionCode = "";
    Say("making the session...");
    Together::CreateLobby(type, maxPlayers);
    Set(CreatingLobby);
}

void JoinByCode(const string &in typed)
{
    if (Busy() || InSession())
        return;
    joinCode = CleanCode(typed);
    if (joinCode.length() != 8)
    {
        Say("a code is eight letters and numbers", true);
        return;
    }
    Say("looking for " + joinCode + "...");
    Together::FindLobbies(CodeKey(joinCode));
    Set(FindingCode);
}

// Joining by code: the next session whose key matched (the one whose host answers the code is the one).
bool TryNextCandidate()
{
    if (candidates.length() == 0)
        return false;
    string id = candidates[0], code = joinCode;
    candidates.removeAt(0);
    Set(Idle);
    JoinById(id, code);
    return true;
}

void JoinById(const string &in id, const string &in code = "")
{
    if (Busy() || InSession() || id == "")
        return;
    joinId = id;
    joinCode = code;
    Together::SetJoinCode(code);
    Say("joining...");
    Together::JoinLobby(id);
    Set(JoiningLobby);
}

// Back out of whatever is going on: a session (leaving it, back to the main menu), or one being started.
void Leave()
{
    bool wasIn = phase != Idle;
    string what = phase == Hosting ? "you ended the session" : (Busy() ? "cancelled" : "you left the session");
    bool editor = phase == Hosting || phase == Joined || phase == Connecting || phase == OpeningEditor;
    Together::HostNextEditor(false);
    Together::SetSessionCode("");
    Together::SetJoinCode("");
    Together::LeaveLobby();
    if (editor || Together::IsHosting() || Together::IsJoined())
        Together::Leave();          // back to the main menu
    Set(Idle);
    if (wasIn)
        Say(what);
}

// The host's name as Steam has it (the lobby's owner: its first member), not what the lobby's data says.
string HostName()
{
    array<string>@ names = Together::LobbyMembers();
    return names.length() > 0 ? names[0] : Together::LobbyData("host");
}

// --- every frame ---------------------------------------------------------------------------------------------------

string Code() { return sessionCode; }

void Update()
{
    // what the host DLL refused or ended (a save, a group, the host leaving...)
    string hostNotice = Together::TakeNotice();
    if (hostNotice != "")
    {
        Notify(hostNotice);
        if ((phase == Joined || phase == Connecting || phase == JoiningLobby) && hostNotice.findFirst("the host ") == 0)
            hostSaid = true;            // the generic "the session ended" isn't needed after the host's own reason
    }

    // an invite accepted in Steam (or the command line Steam started the game with)
    string invite = Together::TakeInvite();
    if (invite != "")
    {
        if (phase == Hosting || phase == OpeningEditor || (phase == Idle && Editor::IsOpen()))
        {
            // the notice offers "join now": their own map's unsaved changes (and their session) are theirs to keep
            pendingInvite = invite;
            inviteNotice = phase == Idle ? "you have an invite to a session: save your map first, then press join now"
                                         : "you have an invite to another session: save your map, then press join now to end yours and join";
            Notify(inviteNotice);
        }
        else
            JoinInvite(invite);
    }

    // an invite waiting for the player to be back on the menu
    if (joinAfter != "" && phase == Idle && !Editor::IsOpen() && !Together::IsJoined() && !Together::IsHosting())
    {
        string id = joinAfter;
        joinAfter = "";
        JoinById(id);
    }

    // a non-error message fades after a while (not while something is under way: it says what to do)
    if (message != "" && !messageBad && !Busy() && Host::Time() - messageAt > 10)
        message = "";

    string lobby = Together::LobbyState();
    double waited = Host::Time() - phaseSince;
    switch (phase)
    {
    case CreatingLobby:
        if (lobby == "in lobby")
        {
            // not listed, nor joinable, until the editor listens
            Together::SetLobbyJoinable(false);
            if (CanHaveCode(startType))
            {
                sessionCode = NewCode();
                Together::SetSessionCode(sessionCode);
                Together::SetLobbyData("ch", CodeKey(sessionCode));
            }
            Together::SetLobbyData("host", Together::OwnName());
            Together::SetLobbyData("ver", VERSION);
            Together::SetLobbyData("vis", VisibilityName(startType));
            Together::SetLobbyData("map", startMap == "" ? "new map" : MapTitle(startMap));
            Together::HostNextEditor(true);
            if (!Together::HostNextArmed())
            {
                Fail("this game can't host a session (Steam networking isn't available)");
                return;
            }
            Set(OpeningEditor);             // first: opening a map is a long call
            Say(startMap == "" ? "name your new map in the game's dialog to start the session (cancel to stop)" : "opening the editor...");
            bool opened = startMap == "" ? Together::NewMap() : Together::OpenMap(startMap);
            if (!opened)
                Fail("the editor couldn't be opened");
        }
        else if (lobby.findFirst("error") == 0)
            Fail(lobby.substr(7));
        break;
    case OpeningEditor:
        // listening is enough: a new map asks for its name first (the editor opens once it has one)
        if (Together::IsHosting())
        {
            Together::SetLobbyData("addr", Together::OwnAddress());
            Together::SetLobbyData("ct", "1");
            Together::SetLobbyJoinable(true);
            joinable = true;
            Set(Hosting);
            openTab = true;
            Say(sessionCode != "" ? "hosting: code " + sessionCode : "hosting");
        }
        // a new map waits for its name as long as the player takes on the Create page; going elsewhere stops it, so
        // nothing they open later is shared without them asking
        else if (!Editor::IsOpen() && waited > 3 && !Page::win.IsTabOpen())
            Fail("the session wasn't started (you left the create together page)");
        else if (Editor::IsOpen() && waited > 30)
            Fail("the editor didn't open as a session");
        break;
    case Hosting:
        if (!Together::IsHosting())
        {
            if (endingSince < 0)
                endingSince = Host::Time();
            else if (Host::Time() - endingSince > 2)
            {
                Together::LeaveLobby();
                Together::SetSessionCode("");
                Set(Idle);
                Notify("your session ended");
            }
            return;
        }
        endingSince = -1;
        {
            string name = Editor::MapName();
            if (name != "" && name != Together::LobbyData("map"))
                Together::SetLobbyData("map", name);
            bool room = Together::Players() < Together::LobbyMaxPlayers();
            if (room != joinable)
            {
                joinable = room;
                Together::SetLobbyJoinable(room);
            }
        }
        break;
    case FindingCode:
        if (!Together::Searching())
        {
            int n = Together::FoundCount();
            string key = CodeKey(joinCode);
            candidates.resize(0);
            for (int i = 0; i < n; i++)
                if (Together::FoundData(i, "ch") == key)
                {
                    if (Together::FoundIsFriend(i))
                        candidates.insertAt(0, Together::FoundId(i));      // a friend's first
                    else
                        candidates.insertLast(Together::FoundId(i));
                }
            if (!TryNextCandidate())
                Fail("no open session has the code " + joinCode + ": check it, or the session may be full");
        }
        else if (waited > 20)
            Fail("Steam didn't answer: try again");
        break;
    case JoiningLobby:
        if (lobby == "in lobby")
        {
            string ver = Together::LobbyData("ver"), addr = Together::LobbyData("addr");
            if (ver != VERSION)
            {
                Fail("the host has Create Together " + (ver == "" ? "?" : ver) + ", you have " + VERSION + ": update to the same version");
                return;
            }
            if (addr == "")
            {
                Fail("that session isn't open yet (the host is still starting it): try again in a moment");
                return;
            }
            // the editor must be the lobby owner's: a lobby can't send anyone elsewhere
            if (Together::Backend() == "steam" && addr != "steam." + Together::LobbyOwnerId())
            {
                Fail("that session's address isn't its host's");
                return;
            }
            // by code: only a session whose host knows the code (it answers this player's proof)
            if (joinCode != "" && !Together::CodeAccepted())
            {
                if (waited > 12)
                {
                    Together::LeaveLobby();
                    if (!TryNextCandidate())
                        Fail("that session didn't take the code " + joinCode + ": check it with the host");
                }
                return;
            }
            Set(Connecting);                // first: the join starts the engine's connection inside the call
            Say("connecting to " + HostName() + "...");
            if (!Together::Join(addr))
                Fail("couldn't connect to that session");
        }
        else if (lobby.findFirst("error") == 0)
            Fail(lobby.substr(7));
        else if (waited > 30)
            Fail("Steam didn't answer: try again");
        break;
    case Connecting:
        if (hostSaid && !Together::IsJoined())
        {
            hostSaid = false;
            Together::LeaveLobby();
            Together::SetJoinCode("");
            Set(Idle);
            Say("you couldn't join that session", true);
        }
        else if (Together::IsJoined() && Editor::IsOpen())
        {
            Set(Joined);
            openTab = true;
            Say("joined " + HostName() + "'s session");
        }
        else if (waited > 90)
            Fail("couldn't reach the host's editor");
        break;
    case Joined:
        if (!Together::IsJoined() || lobby != "in lobby")
        {
            if (endingSince < 0)
                endingSince = Host::Time();
            else if (Host::Time() - endingSince > 2)
            {
                Together::LeaveLobby();
                Together::SetJoinCode("");
                if (Together::IsJoined())
                    Together::Leave();
                Set(Idle);
                if (!hostSaid)
                    Notify("the session ended: the host left, or the connection dropped");
                hostSaid = false;
            }
            return;
        }
        endingSince = -1;
        break;
    default:
        break;
    }
}

// An invite: joined at once from the menu, or after leaving what the player is in (back on the menu first).
void JoinInvite(const string &in id)
{
    pendingInvite = "";
    inviteNotice = "";
    if (InSession() || Busy() || Editor::IsOpen())
    {
        if (InSession() || Busy())
            Leave();
        else
            Together::Leave();          // their own map, which they chose to leave
        joinAfter = id;
    }
    else
        JoinById(id);
}

// What Steam or the lobby said, in this plugin's words.
string Words(const string &in why)
{
    string s = why;
    int at = s.findFirst("lobby");
    while (at >= 0)
    {
        s = s.substr(0, at) + "session" + s.substr(at + 5);
        at = s.findFirst("lobby", at + 7);
    }
    return s;
}

void Fail(const string &in why)
{
    bool editor = phase == Connecting || phase == OpeningEditor;
    Together::HostNextEditor(false);
    Together::SetSessionCode("");
    Together::SetJoinCode("");
    Together::LeaveLobby();
    if (editor && (Together::IsJoined() || Together::IsHosting() || phase == Connecting))
        Together::Leave();              // a join under way too (back to the menu)
    Set(Idle);
    Say(Words(why), true);
    if (!Page::win.IsTabOpen())         // on the page it's in red there already
        Notify(Words(why));
}

}  // namespace Session
