using System.Xml.Linq;
using Shared;
using GameServer.realm;

namespace GameServer.logic.behaviors; 

internal class Orbit : CycleBehavior
{
    //State storage: orbit state
    private class OrbitState
    {
        public float Speed;
        public float Radius;
        public int Direction;
    }

    private float speed;
    private float acquireRange;
    private float radius;
    private ushort? target;
    private float speedVariance;
    private float radiusVariance;
    private bool? orbitClockwise;
        
    public Orbit(XElement e)
    {
        speed = e.ParseFloat("@speed");
        radius = e.ParseFloat("@radius");
        acquireRange = e.ParseFloat("@acquireRange");
        target = GetObjType(e.ParseString("@target"));
        speedVariance = e.ParseNFloat("@speedVariance") ?? speed * 0.1f;
        radiusVariance = e.ParseNFloat("@radiusVariance") ?? speed * 0.1f;
        orbitClockwise = e.ParseBool("@orbitClockwise");
    }
        
    public Orbit(double speed, double radius, double acquireRange = 10,
        string target = null, double? speedVariance = null, double? radiusVariance = null,
        bool? orbitClockwise = false)
    {
        this.speed = (float)speed;
        this.radius = (float)radius;
        this.acquireRange = (float)acquireRange;
        this.target = target == null ? null : (ushort?)GetObjType(target);
        this.speedVariance = (float)(speedVariance ?? speed * 0.1);
        this.radiusVariance = (float)(radiusVariance ?? speed * 0.1);
        this.orbitClockwise = orbitClockwise;
    }

    protected override void OnStateEntry(Entity host, RealmTime time, ref object state)
    {
        int orbitDir;
        if (orbitClockwise == null)
            orbitDir = (Random.Next(1, 3) == 1) ? 1 : -1;
        else
            orbitDir = ((bool)orbitClockwise) ? 1 : -1;

        state = new OrbitState()
        {
            Speed = speed + speedVariance * (float)(Random.NextDouble() * 2 - 1),
            Radius = radius + radiusVariance * (float)(Random.NextDouble() * 2 - 1),
            Direction = orbitDir
        };
    }

    protected override void TickCore(Entity host, RealmTime time, ref object state)
    {
        var s = (OrbitState)state;

        Status = CycleStatus.NotStarted;
            
        var entity = host.AttackTarget ?? host.GetNearestEntity(acquireRange, target);

        if (entity != null)
        {
            double angle;
            if (host.Y == entity.Y && host.X == entity.X)//small offset
                angle = Math.Atan2(host.Y - entity.Y + (Random.NextDouble() * 2 - 1), host.X - entity.X + (Random.NextDouble() * 2 - 1));
            else
                angle = Math.Atan2(host.Y - entity.Y, host.X - entity.X);
            var angularSpd = s.Direction * host.GetSpeed(s.Speed) / s.Radius;
            angle += angularSpd * (time.ElapsedUsDelta / (1000f * 1000f));

            var x = entity.X + Math.Cos(angle) * s.Radius;
            var y = entity.Y + Math.Sin(angle) * s.Radius;
            var vect = new Vector2((float)x, (float)y) - new Vector2(host.X, host.Y);
            vect.Normalize();
            vect *= host.GetSpeed(s.Speed) * (time.ElapsedUsDelta / (1000f * 1000f));

            host.ValidateAndMove(host.X + vect.X, host.Y + vect.Y);

            Status = CycleStatus.InProgress;
        }

        state = s;
    }
}