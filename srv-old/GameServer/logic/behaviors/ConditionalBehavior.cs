using System.Xml.Linq;
using Shared;
using GameServer.realm;

namespace GameServer.logic.behaviors; 

public class ConditionalBehavior : Behavior
{
    private readonly ConditionEffects effect;
    private readonly Behavior behavior;

    public ConditionalBehavior(XElement e, IStateChildren[] children)
    {
        foreach (var child in children)
        {
            if (child is not Behavior bh)
            {
                continue;
            }
                
            behavior = bh;
            break;
        }

        effect = (ConditionEffects)Enum.Parse(typeof(ConditionEffects), e.ParseString("@effect"));
    }
        
    public ConditionalBehavior(ConditionEffects effect, Behavior behavior)
    {
        this.effect = effect;
        this.behavior = behavior;
    }

    protected override void OnStateEntry(Entity host, RealmTime time, ref object state)
    {
        behavior.OnStateEntry(host, time);
    }

    protected override void TickCore(Entity host, RealmTime time, ref object state)
    {
        if (host.HasConditionEffect(effect))
            behavior.Tick(host, time);
    }
}