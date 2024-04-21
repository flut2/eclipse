using System.Xml.Linq;
using Shared;
using Shared.resources;
using GameServer.realm;
using GameServer.realm.entities;

namespace GameServer.logic.behaviors; 

internal class Shoot : CycleBehavior
{
    //State storage: cooldown timer

    private readonly float _radius;
    private readonly int _count;
    private readonly float _shootAngle;
    private readonly float? _fixedAngle;
    private readonly float? _rotateAngle;
    private readonly float _angleOffset;
    private readonly float? _defaultAngle;
    private readonly float _predictive;
    private readonly int _projectileIndex;
    private readonly long _coolDownOffset;
    private Cooldown _coolDown;
    private readonly bool _shootLowHp;
    private readonly ushort? _target;

    private int _rotateCount;

    public Shoot(XElement e)
    {
        _radius = e.ParseFloat("@radius", 5);
        _count = e.ParseInt("@count", 1);
        _shootAngle = _count == 1 ? 0 : (float)((e.ParseNFloat("@shootAngle") ?? 360.0 / _count) * Math.PI / 180);
        _projectileIndex = e.ParseInt("@projectileIndex");
        _fixedAngle = (float?)(e.ParseNFloat("@fixedAngle") * Math.PI / 180);
        _rotateAngle = (float?)(e.ParseNFloat("@rotateAngle") * Math.PI / 180);
        _angleOffset = (float)(e.ParseFloat("@angleOffset") * Math.PI / 180);
        _defaultAngle = (float?)(e.ParseNFloat("@defaultAngle") * Math.PI / 180);
        _predictive = e.ParseFloat("@predictive");
        _coolDownOffset = e.ParseLong("@coolDownOffset") * 1000;
        _coolDown = new Cooldown().Normalize(e.ParseLong("@cooldown", 1000) * 1000);
        _shootLowHp = e.ParseBool("@shootLowHp");
        _target = e.ParseString("@target") == null ? null : GetObjType(e.ParseString("@target"));
    }

    protected override void OnStateEntry(Entity host, RealmTime time, ref object state)
    {
        state = _coolDownOffset;
    }

    private static float Predict(Entity host, Entity target, ProjectileDesc desc)
    {
        // trying prod prediction

        const int PREDICT_NUM_TICKS = 4; // magic determined by experiement
        var history = target.TryGetHistory(1);

        if (history == null)
        {
            return (float)Math.Atan2(target.Y - host.Y, target.X - host.X);
        }

        var targetX = target.X + PREDICT_NUM_TICKS *
            (target.X - history.Value.X);
        var targetY = target.Y + PREDICT_NUM_TICKS *
            (target.Y - history.Value.Y);

        var angle = (float)Math.Atan2(targetY - host.Y, targetX - host.X);

        return angle;
    }

    protected override void TickCore(Entity host, RealmTime time, ref object state)
    {
        var cool = (long?)state ??
                   -1; // <-- crashes server due to state being null... patched now but should be looked at.
        Status = CycleStatus.NotStarted;

        if (cool <= 0)
        {
            var count = _count;

            Entity player;
            if (host.AttackTarget != null)
                player = host.AttackTarget;
            else
                player = _shootLowHp
                    ? host.GetLowestHpEntity(_radius, _target)
                    : host.GetNearestEntity(_radius, _target);

            if (host.TauntedPlayerNearby(_radius))
                player = host.GetNearestTauntedPlayer(_radius);

            if (player != null || _defaultAngle != null || _fixedAngle != null)
            {
                var desc = host.ObjectDesc.Projectiles[_projectileIndex];

                float a;

                if (_fixedAngle != null)
                {
                    a = (float)_fixedAngle;
                }
                else if (player != null)
                {
                    if (_predictive != 0 && _predictive > Random.NextDouble())
                    {
                        a = Predict(host, player, desc);
                    }
                    else
                    {
                        a = (float)Math.Atan2(player.Y - host.Y, player.X - host.X);
                    }
                }
                else if (_defaultAngle != null)
                {
                    a = (float)_defaultAngle;
                }
                else
                {
                    a = 0;
                }

                a += _angleOffset + ((_rotateAngle != null) ? (float)_rotateAngle * _rotateCount : 0);
                _rotateCount++;

                var dmg = desc.Damage;

                var startAngle = a - _shootAngle * (count - 1) / 2;
                byte prjId = 0;
                var prjPos = new Position() { X = host.X, Y = host.Y };
                var prjs = new Projectile[count];
                for (var i = 0; i < count; i++)
                {
                    var prj = host.CreateProjectile(
                        desc, host.ObjectType,
                        prjPos.X, prjPos.Y);
                    host.Owner.EnterWorld(prj);

                    if (i == 0)
                        prjId = prj.BulletId;

                    prjs[i] = prj;
                }
                    
                foreach (var p in host.Owner.Players.Values)
                    if (MathUtils.DistSqr(host.X, host.Y, p.X, p.Y) < 20 * 20)
                        p.Client.SendEnemyShoot(prjId, host.Id, (byte)(desc.BulletType), host.X, host.Y,
                            startAngle, (short)desc.Damage, (short)desc.MagicDamage, (short)desc.TrueDamage, (byte)count, _shootAngle);
            }

            cool = _coolDown.Next(Random);
            Status = CycleStatus.Completed;
        }
        else
        {
            cool -= time.ElapsedUsDelta;
            Status = CycleStatus.InProgress;
        }

        state = cool;
    }
}