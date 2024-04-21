using System.Xml.Linq;
using Shared;
using GameServer.realm;

namespace GameServer.logic.behaviors; 

internal class Buzz : CycleBehavior
{
    //State storage: direction & remain
    private class BuzzStorage
    {
        public Vector2 Direction;
        public float RemainingDistance;
    }


    private float speed;

    private float dist;
        
    public Buzz(XElement e)
    {
        speed = e.ParseFloat("@speed");
        dist = e.ParseFloat("@dist");
    }
        
    public Buzz(double speed = 2, double dist = 0.5)
    {
        this.speed = (float)speed;
        this.dist = (float)dist;
    }

    protected override void OnStateEntry(Entity host, RealmTime time, ref object state)
    {
        state = new BuzzStorage();
    }

    protected override void TickCore(Entity host, RealmTime time, ref object state)
    {
        var storage = (BuzzStorage)state;

        Status = CycleStatus.NotStarted;
            
        Status = CycleStatus.InProgress;
        if (storage.RemainingDistance <= 0)
        {
            do
            {
                storage.Direction = new Vector2(Random.Next(-1, 2), Random.Next(-1, 2));
            } while (storage.Direction.X == 0 && storage.Direction.Y == 0);
            storage.Direction.Normalize();
            storage.RemainingDistance = this.dist;
            Status = CycleStatus.Completed;
        }
        var dist = host.GetSpeed(speed) * (time.ElapsedUsDelta / (1000f * 1000f));
        host.ValidateAndMove(host.X + storage.Direction.X * dist, host.Y + storage.Direction.Y * dist);

        storage.RemainingDistance -= dist;

        state = storage;
    }
}