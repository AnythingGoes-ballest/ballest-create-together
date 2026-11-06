// Create Together: edit one map with other players.
//   - a "create together" page in the Create menu: open sessions (public ones and your friends'), join one with its
//     code, or start your own from a new map or one of your saved maps, choosing who can join (public, friends, anyone
//     with the code, Steam invites only) and how many players;
//   - in the editor, a "together" tab (the code, who's there, Steam invites, leave) and a badge at the top.
// The host's editor opens as a listen server (the game's own editor networking: its pieces and editing pawns are
// replicated, every change goes through the host); joiners connect to it over Steam, found through a Steam lobby.

void Main()
{
    Page::Build();
    Tab::Build();
    Log::Info("create together ready (" + Together::Backend() + ")");
}

void Update(float dt)
{
    Session::Update();
    Page::Update();
    Tab::Update();
}
