// The session: hosting one (a lobby, then the editor opened as a listen server) or joining one (the lobby, then the
// editor over the network). The editor's own replication does the editing; this only gets everyone into the same
// editor and keeps the lobby saying where it is.
//
// The lobby's data, read by everyone who lists it:
//   ct=1 (the host's own tag), code, map, host (the host's name), addr (where the editor is: Together::OwnAddress),
//   ver (this plugin's version: other versions can't join), vis (who can join, for the list's badge).

const string VERSION = "0.1.0";

namespace Session
{

enum Phase
{
    Idle,
    CreatingLobby,      // hosting: the lobby is being made
    OpeningEditor,      // hosting: the editor is opening as a listen server
    Hosting,
    FindingCode,        // joining by code: looking for the lobby
    JoiningLobby,
    Connecting,         // joining: the editor is loading from the host
    Joined
}

Phase phase = Idle;
string message;                 // what happened last, for the windows ("" for nothing)
bool messageBad = false;
double phaseSince = 0;

// the session being started
Together::LobbyType startType = Together::Public;
int startMax = 4;
string startMap;                // a saved map's file, or "" for a new map
string joinCode;
string joinId;

void Set(Phase p)
{
    phase = p;
    phaseSince = Host::Time();
}

void Say(const string &in text, bool bad = false)
{
    message = text;
    messageBad = bad;
    if (text != "")
        Log::Info(text);
}

bool Busy() { return phase != Idle && phase != Hosting && phase != Joined; }
bool InSession() { return phase == Hosting || phase == Joined; }

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

// --- starting ------------------------------------------------------------------------------------------------------

void StartHosting(Together::LobbyType type, int maxPlayers, const string &in mapFile)
{
    if (Busy() || InSession())
        return;
    startType = type;
    startMax = maxPlayers;
    startMap = mapFile;
    Say("making the session...");
    Together::CreateLobby(type, maxPlayers);
    Set(CreatingLobby);
}

void JoinByCode(const string &in typed)
{
    if (Busy() || InSession())
        return;
    joinCode = CleanCode(typed);
    if (joinCode.length() != 6)
    {
        Say("a code is six letters and numbers", true);
        return;
    }
    Say("looking for " + joinCode + "...");
    Together::FindLobbies(joinCode);
    Set(FindingCode);
}

void JoinById(const string &in id)
{
    if (Busy() || InSession() || id == "")
        return;
    joinId = id;
    Say("joining...");
    Together::JoinLobby(id);
    Set(JoiningLobby);
}

void Leave()
{
    bool wasIn = phase != Idle;
    Together::HostNextEditor(false);
    Together::LeaveLobby();
    if (Together::IsHosting() || Together::IsJoined())
        Together::Leave();          // back to the main menu
    Set(Idle);
    if (wasIn)
        Say("you left the session");
}

// --- every frame ---------------------------------------------------------------------------------------------------

string Code() { return Together::LobbyData("code"); }

void Update()
{
    // an invite accepted in Steam (or the command line Steam started the game with)
    string invite = Together::TakeInvite();
    if (invite != "")
    {
        if (InSession() || Busy())
            Leave();
        JoinById(invite);
    }

    string lobby = Together::LobbyState();
    double waited = Host::Time() - phaseSince;
    switch (phase)
    {
    case CreatingLobby:
        if (lobby == "in lobby")
        {
            string id = Together::LobbyId();
            Together::SetLobbyData("code", CodeFor(id));
            Together::SetLobbyData("host", Together::OwnName());
            Together::SetLobbyData("addr", Together::OwnAddress());
            Together::SetLobbyData("ver", VERSION);
            Together::SetLobbyData("vis", VisibilityName(startType));
            Together::SetLobbyData("map", startMap == "" ? "new map" : MapTitle(startMap));
            Together::HostNextEditor(true);
            Set(OpeningEditor);             // first, as for joining: opening a map is a long call
            Say("opening the editor...");
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
            Set(Hosting);
            Say("hosting: code " + Code());
        }
        else if (waited > 45)
            Fail("the editor didn't open as a session");
        break;
    case Hosting:
        if (!Together::IsHosting())
        {
            Together::LeaveLobby();
            Set(Idle);
            Say("the session ended");
            return;
        }
        {
            string name = Editor::MapName();
            if (name != "" && name != Together::LobbyData("map"))
                Together::SetLobbyData("map", name);
        }
        break;
    case FindingCode:
        if (!Together::Searching())
        {
            int n = Together::FoundCount();
            if (n == 0)
            {
                Fail("no session has the code " + joinCode);
                return;
            }
            JoinFound(Together::FoundId(0));
        }
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
                Fail("the session has no editor yet: try again in a moment");
                return;
            }
            // the phase first: the join starts the engine's connection inside this call, which can take this frame's
            // whole budget (the host then cuts the script short)
            Set(Connecting);
            Say("connecting to " + Together::LobbyData("host") + "...");
            Together::Join(addr);
        }
        else if (lobby.findFirst("error") == 0)
            Fail(lobby.substr(7));
        break;
    case Connecting:
        if (Together::IsJoined() && Editor::IsOpen())
        {
            Set(Joined);
            Say("joined " + Together::LobbyData("host") + "'s session");
        }
        else if (waited > 90)
            Fail("couldn't reach the host's editor");
        break;
    case Joined:
        if (!Together::IsJoined())
        {
            Together::LeaveLobby();
            Set(Idle);
            Say("the session ended (the host left or the connection dropped)");
        }
        break;
    default:
        break;
    }
}

void JoinFound(const string &in id)
{
    Set(Idle);
    JoinById(id);
}

void Fail(const string &in why)
{
    Together::HostNextEditor(false);
    Together::LeaveLobby();
    Set(Idle);
    Say(why, true);
}

}  // namespace Session
