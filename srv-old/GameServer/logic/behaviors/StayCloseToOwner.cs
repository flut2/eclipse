using System.Xml.Linq;
using Shared;
using GameServer.realm;

namespace GameServer.logic.behaviors; 

internal class StayCloseToOwner : CycleBehavior
{
    //State storage: target position
    //assume spawn=state entry position

    private float speed;
    private int range;

    public StayCloseToOwner(XElement e)
    {
        speed = e.ParseFloat("@speed");
        range = e.ParseInt("@range", 5);
    }

    public StayCloseToOwner(double speed, int range = 5)
    {
        this.speed = (float)speed;
        this.range = range;
    }

    protected override void OnStateEntry(Entity host, RealmTime time, ref object state)
    {
        if (host.GetPlayerOwner() is not null)
        {
            state = new Vector2(host.GetPlayerOwner().X, host.GetPlayerOwner().Y);
            return;
        }
        state = new Vector2(host.X, host.Y);
    }

    protected override void TickCore(Entity host, RealmTime time, ref object state)
    {
        if (host.GetPlayerOwner() is null) return;
        Status = CycleStatus.NotStarted;

        if (state is not Vector2)
        {
            state = new Vector2(host.GetPlayerOwner().X, host.GetPlayerOwner().Y);
            Status = CycleStatus.Completed;
            return;
        }

        var vect = (Vector2)state;
        var ownerPos = new Vector2(host.GetPlayerOwner().X, host.GetPlayerOwner().Y);
        if (vect.Length() > ownerPos.Length() + range)
            state = new Vector2(host.GetPlayerOwner().X, host.GetPlayerOwner().Y);

        if ((vect - new Vector2(host.X, host.Y)).Length() > range)
        {
            vect -= new Vector2(host.X, host.Y);
            vect.Normalize();
            var dist = host.GetSpeed(speed) * (time.ElapsedUsDelta / (1000f * 1000f));
            host.ValidateAndMove(host.X + vect.X * dist, host.Y + vect.Y * dist);

            Status = CycleStatus.InProgress;
            return;
        }

        Status = CycleStatus.Completed;
    }
}