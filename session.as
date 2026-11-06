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
string notice;                  // something the player must see wherever they are (the notice window)
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

void Set(Phase p)
{
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
    notice = text;
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

// A new code: 8 letters and digits that can't be mixed up, from the clock and this player, mixed many times (there is
// no random source in the API; the code only has to be hard to guess from outside).
string NewCode()
{
    uint h1 = 2166136261, h2 = 374761393;
    string seed = "" + Host::Time() + "|" + Together::OwnId() + "|" + Together::LobbyId();
    for (int round = 0; round < 64; round++)
        for (uint i = 0; i < seed.length(); i++)
        {
            h1 = (h1 ^ seed[i]) * 16777619;
            h2 = (h2 ^ (h1 >> 7)) * 2246822519;
        }
    string code;
    for (int i = 0; i < 8; i++)
    {
        code += CODE_LETTERS.substr((i < 4 ? h1 : h2) % 32, 1);
        if (i < 4)
            h1 = h1 / 32 + h2 * 31;
        else
            h2 = h2 / 32 + h1 * 17;
    }
    return code;
}

// --- starting ------------------------------------------------------------------------------------------------------

void StartHosting(Together::LobbyType type, int maxPlayers, const string &in mapFile)
{
    if (Busy() || InSession())
        return;
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
    bool editor = phase == Hosting || phase == Joined || phase == Connecting || phase == OpeningEditor;
    Together::HostNextEditor(false);
    Together::SetSessionCode("");
    Together::SetJoinCode("");
    Together::LeaveLobby();
    if (editor || Together::IsHosting() || Together::IsJoined())
        Together::Leave();          // back to the main menu
    Set(Idle);
    if (wasIn)
        Say("you left the session");
}

// --- every frame ---------------------------------------------------------------------------------------------------

string Code() { return sessionCode; }

void Update()
{
    // what the host DLL refused or ended (a save, a group, the host leaving...)
    string hostNotice = Together::TakeNotice();
    if (hostNotice != "")
        Notify(hostNotice);

    // an invite accepted in Steam (or the command line Steam started the game with)
    string invite = Together::TakeInvite();
    if (invite != "")
    {
        if (phase == Hosting || phase == OpeningEditor)
            Notify("you have an invite to another session: leave yours first (the together tab), then accept it again");
        else
        {
            if (InSession() || Busy())
                Leave();
            JoinById(invite);
        }
    }

    // a non-error message fades after a while
    if (message != "" && !messageBad && Host::Time() - messageAt > 10)
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
            Say(startMap == "" ? "name your new map to start the session" : "opening the editor...");
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
        else if (waited > 60 && Together::NetMode() != "listen server")
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
            for (int i = 0; i < n; i++)
                if (Together::FoundData(i, "ch") == key)
                {
                    string code = joinCode;
                    Set(Idle);
                    JoinById(Together::FoundId(i), code);
                    return;
                }
            Fail("no session has the code " + joinCode);
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
            Set(Connecting);                // first: the join starts the engine's connection inside the call
            Say("connecting to " + Together::LobbyData("host") + "...");
            if (!Together::Join(addr))
                Fail("couldn't connect to that session");
        }
        else if (lobby.findFirst("error") == 0)
            Fail(lobby.substr(7));
        else if (waited > 30)
            Fail("Steam didn't answer: try again");
        break;
    case Connecting:
        if (Together::IsJoined() && Editor::IsOpen())
        {
            Set(Joined);
            openTab = true;
            Say("joined " + Together::LobbyData("host") + "'s session");
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
                Notify("the session ended: the host left, or the connection dropped");
            }
            return;
        }
        endingSince = -1;
        break;
    default:
        break;
    }
}

void Fail(const string &in why)
{
    bool editor = phase == Connecting || phase == OpeningEditor;
    Together::HostNextEditor(false);
    Together::SetSessionCode("");
    Together::SetJoinCode("");
    Together::LeaveLobby();
    if (editor && (Together::IsJoined() || Together::IsHosting()))
        Together::Leave();
    Set(Idle);
    Say(why, true);
    Notify(why);
}

}  // namespace Session
