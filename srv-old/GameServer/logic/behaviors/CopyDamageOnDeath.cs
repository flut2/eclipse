using System.Xml.Linq;
using Shared;
using GameServer.realm;
using GameServer.realm.entities;

namespace GameServer.logic.behaviors; 

public class CopyDamageOnDeath : Behavior
{
    private float dist;
    private string child;

    public CopyDamageOnDeath(XElement e)
    {
        dist = e.ParseFloat("@dist");
        child = e.ParseString("@child");
    }
        
    public CopyDamageOnDeath(string child, float dist = 50)
    {
        this.dist = dist;
        this.child = child;
    }

    protected internal override void Resolve(State parent)
    {
        parent.Death += (sender, e) =>
        {
            Enemy en;
            if ((en =
                    e.Host.GetNearestEntity(dist,
                        e.Host.Manager.Resources.GameData.IdToObjectType[child]) as Enemy) !=
                null)
            {
                en.SetDamageCounter((e.Host as Enemy).DamageCounter, en);
            }
        };
    }

    protected override void TickCore(Entity host, RealmTime time, ref object state)
    {
    }
}