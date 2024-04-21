using System.Xml.Linq;
using Shared;
using GameServer.realm;
using GameServer.realm.entities;

namespace GameServer.logic.behaviors; 

public class CopyDamage : Behavior
{
    private float dist;
    private string child;

    public CopyDamage(XElement e)
    {
        dist = e.ParseFloat("@dist");
        child = e.ParseString("@child");
    }

    public CopyDamage(string child, float dist = 50)
    {
        this.dist = dist;
        this.child = child;
    }

    protected override void OnStateEntry(Entity host, RealmTime time, ref object state)
    {
        Enemy en;
        if ((en = host.GetNearestEntity(dist, host.Manager.Resources.GameData.IdToObjectType[child]) as Enemy) !=
            null)
        {
            en.SetDamageCounter(((Enemy)host).DamageCounter, en);
        }
    }

    protected override void TickCore(Entity host, RealmTime time, ref object state)
    {
    }
}