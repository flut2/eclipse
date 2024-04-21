using System.Xml.Linq;
using GameServer.realm;

namespace GameServer.logic.behaviors; 

public class OnDeathBehavior : Behavior
{
    private readonly Behavior behavior;

    public OnDeathBehavior(XElement e, IStateChildren[] children)
    {
        foreach (var child in children)
        {
            if (child is Behavior bh)
            {
                behavior = bh;
                break;
            }
        }
    }
        
    public OnDeathBehavior(Behavior behavior)
    {
        this.behavior = behavior;
    }

    protected internal override void Resolve(State parent)
    {
        parent.Death += (s, e) =>
        {
            behavior.OnStateEntry(e.Host, e.Time);
        };
    }

    protected override void TickCore(Entity host, RealmTime time, ref object state)
    {
    }
}