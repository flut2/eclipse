using System.Xml.Linq;
using Shared;
using GameServer.realm.entities.player;

namespace GameServer.realm.entities; 

public class StaticObject : Entity
{
    //Stats
    public bool Vulnerable { get; private set; }
    public bool Static { get; private set; }
    public bool Hittestable { get; private set; }
    public bool Dying { get; private set; }

    private readonly SV<int> _hp;

    public int HP
    {
        get => _hp.GetValue();
        set => _hp.SetValue(value);
    }

    public static int? GetHP(XElement elem)
    {
        var n = elem.Element("Health");
        if (n != null)
            return Utils.FromString(n.Value);
        else
            return null;
    }

    public StaticObject(RealmManager manager, ushort objType, int? life, bool stat, bool dying, bool hittestable)
        : base(manager, objType)
    {
        _hp = new SV<int>(this, StatsType.HP, 0, dying);
        if (Vulnerable = life.HasValue)
            HP = life.Value;
        Dying = dying;
        Static = stat;
        Hittestable = hittestable;
    }

    protected override void ExportStats(IDictionary<StatsType, object> stats)
    {
        stats[StatsType.HP] = (!Vulnerable) ? int.MaxValue : HP;
        base.ExportStats(stats);
    }

    public override bool HitByProjectile(Projectile projectile, RealmTime time)
    {
        if (!Vulnerable || projectile.ProjectileOwner is not Player p) 
            return true;
        
        var dmg = (int)(StatsManager.GetPhysDamage(this, projectile.PhysDamage, p) + 
                        StatsManager.GetMagicDamage(this, projectile.MagicDamage, p) + 
                        StatsManager.GetTrueDamage(this, projectile.TrueDamage, p));
                
        foreach (var player in Owner.Players.Values)
            if (MathUtils.DistSqr(p.X, p.Y, X, Y) < 16 * 16)
                player.Client.SendDamage(this.Id, 0, (ushort)dmg, !CheckHP(), projectile.BulletId, projectile.ProjectileOwner.Self.Id);
            
        HP -= dmg;

        return true;
    }

    protected bool CheckHP()
    {
        if (HP <= 0)
        {
            var x = (int)(X - 0.5);
            var y = (int)(Y - 0.5);
            if (Owner.Map.Contains(new IntPoint(x, y)))
                if (ObjectDesc != null &&
                    Owner.Map[x, y].ObjType == ObjectType)
                {
                    var tile = Owner.Map[x, y];
                    tile.ObjType = 0;
                    tile.UpdateCount++;
                }

            Owner.LeaveWorld(this);
            return false;
        }

        return true;
    }

    public override void Tick(RealmTime time)
    {
        if (Vulnerable)
        {
            if (Dying)
                HP -= (int)(time.ElapsedUsDelta / (1000f * 1000f));

            CheckHP();
        }

        base.Tick(time);
    }
}