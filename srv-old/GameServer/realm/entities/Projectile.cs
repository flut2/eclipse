using Shared.resources;

namespace GameServer.realm.entities; 

public interface IProjectileOwner
{
    Projectile[] Projectiles { get; }
    Entity Self { get; }
}

public class Projectile : Entity {
    public IProjectileOwner ProjectileOwner;
    public ushort Container;
    public ProjectileDesc ProjDesc;
    private long _elapsed;

    public byte BulletId;
    public int PhysDamage;
    public int MagicDamage;
    public int TrueDamage;

    private readonly HashSet<Entity> _hit = new();

    public Projectile(RealmManager manager, ProjectileDesc desc)
        : base(manager, 0xFFFF)
    {
        ProjDesc = desc;
    }

    public void Destroy()
    {
        Owner?.LeaveWorld(this);
    }

    public override void Dispose()
    {
        base.Dispose();
        ProjectileOwner.Projectiles[BulletId] = null;
        //ProjectileOwner = null;
    }

    public override void Tick(RealmTime time)
    {
        _elapsed += time.ElapsedUsDelta;
        // if (ProjectileOwner is Player) Console.WriteLine(_elapsed + " " + ProjDesc.LifetimeMS);
        if (_elapsed >= ProjDesc.LifetimeMS * 1000 + 1000 * 1000)
        {
            Destroy();
            return;
        }

        base.Tick(time);
    }
    
    public void ForceHit(Entity entity, RealmTime time, int cTime = -1)
    {
        if (_hit.Add(entity))
            entity.HitByProjectile(this, time);

        if (!ProjDesc.MultiHit)
            Destroy();
    }
}