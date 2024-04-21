using System.Xml.Linq;
using GameServer.realm;
using Shared;

namespace GameServer.logic.behaviors; 

internal class Follow : CycleBehavior
{
    //State storage: follow state
    private class FollowState
    {
        public F State;
        public long RemainingTime;
    }

    private enum F
    {
        DontKnowWhere,
        Acquired,
        Resting
    }
        
    public Follow(XElement e)
    {
        _speed = e.ParseFloat("@speed");
        _acquireRange = e.ParseFloat("@acquireRange", 10);
        _range = e.ParseFloat("@range", 6);
        _duration = e.ParseLong("@duration") * 1000;
        _coolDown = new Cooldown().Normalize(e.ParseInt("@cooldown"));
        _followParent = e.ParseBool("@followParent");
    }

    private float _speed;
    private float _acquireRange;
    private float _range;
    private long _duration;
    private Cooldown _coolDown;
    private bool _followParent;
    
    public Follow(double speed, double acquireRange = 10, double range = 6,
        long duration = 0, Cooldown coolDown = new(), bool followParent = false)
    {
        _speed = (float)speed;
        _acquireRange = (float)acquireRange;
        _range = (float)range;
        _duration = duration * 1000;
        _coolDown = coolDown.Normalize(duration == 0 ? 0 : 1000);
        _followParent = followParent;
    }

    protected override void TickCore(Entity host, RealmTime time, ref object state)
    {
        FollowState s;
        if (state == null) s = new FollowState();
        else s = (FollowState)state;

        Status = CycleStatus.NotStarted;
            
        var target = host.AttackTarget ?? host.GetNearestEntity(_acquireRange, null);
        if (_followParent)
            target = host;

        Vector2 vect;
        switch (s.State)
        {
            case F.DontKnowWhere:
                if (target != null && s.RemainingTime <= 0)
                {
                    s.State = F.Acquired;
                    if (_duration > 0)
                        s.RemainingTime = _duration;
                    goto case F.Acquired;
                }

                if (s.RemainingTime > 0)
                    s.RemainingTime -= time.ElapsedUsDelta;
                break;
            case F.Acquired:
                if (target == null)
                {
                    s.State = F.DontKnowWhere;
                    s.RemainingTime = 0;
                    break;
                }

                if (s.RemainingTime <= 0 && _duration > 0)
                {
                    s.State = F.DontKnowWhere;
                    s.RemainingTime = _coolDown.Next(Random);
                    Status = CycleStatus.Completed;
                    break;
                }
                if (s.RemainingTime > 0)
                    s.RemainingTime -= time.ElapsedUsDelta;

                vect = new Vector2(target.X - host.X, target.Y - host.Y);
                if (vect.Length() > _range)
                {
                    Status = CycleStatus.InProgress;
                    vect.X -= Random.Next(-2, 2) / 2f;
                    vect.Y -= Random.Next(-2, 2) / 2f;
                    vect.Normalize();
                    var dist = host.GetSpeed(_speed) * (time.ElapsedUsDelta / (1000f * 1000f));
                    host.ValidateAndMove(host.X + vect.X * dist, host.Y + vect.Y * dist);
                }
                else
                {
                    Status = CycleStatus.Completed;
                    s.State = F.Resting;
                    s.RemainingTime = 0;
                }
                break;
            case F.Resting:
                if (target == null)
                {
                    s.State = F.DontKnowWhere;
                    if (_duration > 0)
                        s.RemainingTime = _duration;
                    break;
                }
                Status = CycleStatus.Completed;
                vect = new Vector2(target.X - host.X, target.Y - host.Y);
                if (vect.Length() > _range + 1)
                {
                    s.State = F.Acquired;
                    s.RemainingTime = _duration;
                    goto case F.Acquired;
                }
                break;

        }

        state = s;
    }
}