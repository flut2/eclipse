using System.Xml.Linq;
using Shared;
using GameServer.realm;

namespace GameServer.logic.transitions; 

internal class WorldTransition : Transition
{
    //State storage: none

    private readonly string _world;

    public WorldTransition(XElement e)
        : base(e.ParseString("@targetState", "root"))
    {
        _world = e.ParseString("@world");
    }
        
    public WorldTransition(string world, string targetState)
        : base(targetState)
    {
        _world = world;
    }

    protected override bool TickCore(Entity host, RealmTime time, ref object state)
    {
        return host.Owner.Name == _world || host.Owner.SBName == _world;
    }
}