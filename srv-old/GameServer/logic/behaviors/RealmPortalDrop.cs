using System.Xml.Linq;
using GameServer.realm;

namespace GameServer.logic.behaviors; 

public class RealmPortalDrop : Behavior
{

    public RealmPortalDrop(XElement e)
    {}
        
    public RealmPortalDrop()
    {}
        
    protected internal override void Resolve(State parent)
    {

        parent.Death += (e, s) =>
        {
            var owner = s.Host.Owner;

            if (owner.Name.Contains("DeathArena") || s.Host.Spawned)
                return;

            var en = s.Host.GetNearestEntity(100, 0x5e4b);
            var portal = Entity.Resolve(s.Host.Manager, "Realm Portal");

            if (en != null)
                portal.Move(en.X, en.Y);
            else
                portal.Move(s.Host.X, s.Host.Y);


            s.Host.Owner.EnterWorld(portal);
        };
            
    }

    protected override void OnStateEntry(Entity host, RealmTime time, ref object state)
    {
        if (host.GetNearestEntity(100, 0x5e4b) != null)
            return;
        var opener = Entity.Resolve(host.Manager, "Realm Portal Opener");
        host.Owner.EnterWorld(opener);
        opener.Move(host.X, host.Y);
           

    }

    protected override void TickCore(Entity host, RealmTime time, ref object state)
    {
    }
}