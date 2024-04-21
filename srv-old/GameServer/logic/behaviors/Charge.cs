using System.Xml.Linq;
using Shared;
using GameServer.realm;
using GameServer.realm.entities;
using GameServer.realm.entities.player;

namespace GameServer.logic.behaviors; 

internal class Charge : CycleBehavior
{
    //State storage: charge state
    public class ChargeState
    {
        public Vector2 Direction;
        public long RemainingTime;
        public Player from;
    }

    private readonly float _speed;
    private readonly float _range;
    private Cooldown _coolDown;
    private readonly bool _targetPlayers;
    private readonly Action<Entity, RealmTime, Entity, ChargeState> _callB;

    public Charge(XElement e)
    {
        _speed = e.ParseFloat("@speed", 4);
        _range = e.ParseFloat("@range", 10);
        _coolDown = new Cooldown().Normalize(e.ParseLong("@cooldown", 2000) * 1000);
    }
        
    public Charge(double speed = 4, float range = 10, Cooldown coolDown = new Cooldown(), bool targetPlayers = true,
        Action<Entity, RealmTime, Entity, ChargeState> callback = null
    )
    {
        _speed = (float)speed;
        _range = range;
        _coolDown = coolDown.Normalize(2000);
        _targetPlayers = targetPlayers;
        _callB = callback;
    }

    protected override void TickCore(Entity host, RealmTime time, ref object state)
    {
        var s = (state == null) ? 
            new ChargeState() : 
            (ChargeState) state;

        Status = CycleStatus.NotStarted;

        if (s.RemainingTime <= 0)
        {
            if (s.Direction == Vector2.Zero)
            {
                var player = host.GetNearestEntity(_range, _targetPlayers, predicate: (i) => {
                    return _targetPlayers ? true : i is Enemy;
                });
                if (player != null && player.X != host.X && player.Y != host.Y)
                {
                    s.Direction = new Vector2(player.X - host.X, player.Y - host.Y);
                    var d = s.Direction.Length();
                    if(d < 1)
                    {
                        s.from = host.GetPlayerOwner();
                        if (_callB != null)
                            _callB(host, time, player, s);
                        //Cheaty way of later setting s.RemainingTime to 0
                        d = 0;
                    }
                    s.Direction.Normalize();
                    //s.RemainingTime = _coolDown.Next(Random);
                    //if (d / host.GetSpeed(_speed) < s.RemainingTime)
                    s.RemainingTime = (int)(d / host.GetSpeed(_speed) * 1000);
                    Status = CycleStatus.InProgress;
                }
            }
            else
            {
                s.Direction = Vector2.Zero;
                s.RemainingTime = _coolDown.Next(Random);
                Status = CycleStatus.Completed;
            }
        }

        if (s.Direction != Vector2.Zero)
        {
            var dist = host.GetSpeed(_speed) * (time.ElapsedUsDelta / (1000f * 1000f));
            host.ValidateAndMove(host.X + s.Direction.X * dist, host.Y + s.Direction.Y * dist);
            Status = CycleStatus.InProgress;
        }

        s.RemainingTime -= time.ElapsedUsDelta;

        state = s;
    }
}