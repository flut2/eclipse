using System.Xml.Linq;
using Shared;
using Shared.terrain;
using GameServer.realm;
using GameServer.realm.worlds.logic;

namespace GameServer.logic.behaviors; 

internal class StayInRegion : CycleBehavior
{
    //State storage: target position
    //assume spawn=state entry position

    private TileRegion _region;
    private float _speed;
    private int _range;

    public StayInRegion(XElement e)
    {
        _region = (TileRegion)Enum.Parse(typeof(TileRegion), e.ParseString("@region"));
        _speed = e.ParseFloat("@speed");
        _range = e.ParseInt("@range", 3);
    }

    public StayInRegion(TileRegion region, double speed, int range = 3)
    {
        _region = region;
        _speed = (float)speed;
        _range = range;
    }

    protected override void OnStateEntry(Entity host, RealmTime time, ref object state)
    {
        state = new Vector2(host.X, host.Y);
    }

    protected override void TickCore(Entity host, RealmTime time, ref object state)
    {
        Status = CycleStatus.NotStarted;
            
        if (state is not Vector2)
        {
            state = new Vector2(host.X, host.Y);
            Status = CycleStatus.Completed;
            return;
        }

        var tile = host.Owner.Map[(int)host.X, (int)host.Y];
        if (tile.Region == _region)
        {
            return;
        }

        var vect = (Vector2)state;
        if ((vect - new Vector2(host.X, host.Y)).Length() > _range)
        {
            vect -= new Vector2(host.X, host.Y);
            vect.Normalize();
            var dist = host.GetSpeed(_speed) * (time.ElapsedUsDelta / (1000f * 1000f));
            host.ValidateAndMove(host.X + vect.X * dist, host.Y + vect.Y * dist);

            Status = CycleStatus.InProgress;
        }
        else
            Status = CycleStatus.Completed;
    }
}