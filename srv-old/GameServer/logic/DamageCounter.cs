using Shared;
using GameServer.realm;
using GameServer.realm.entities;
using GameServer.realm.entities.player;

namespace GameServer.logic; 

public class DamageCounter
{
    private Enemy _enemy;

    public Enemy Host => _enemy;

    public Projectile LastProjectile { get; private set; }
    public Player LastHitter { get; private set; }

    public DamageCounter Corpse { get; set; }
    public DamageCounter Parent { get; set; }

    private WeakDictionary<Player, int> hitters = new();

    public DamageCounter(Enemy enemy)
    {
        _enemy = enemy;
    }

    public void HitBy(Player player, RealmTime time, Projectile projectile, int dmg)
    {
        if (!hitters.TryGetValue(player, out var totalDmg))
            totalDmg = 0;
        totalDmg += dmg;
        hitters[player] = totalDmg;

        LastProjectile = projectile;
        LastHitter = player;
    }

    public Tuple<Player, int>[] GetPlayerData()
    {
        if (Parent != null)
            return Parent.GetPlayerData();
        var dat = new List<Tuple<Player, int>>();
        foreach (var i in hitters)
        {
            if (i.Key.Owner == null) continue;
            dat.Add(new Tuple<Player, int>(i.Key, i.Value));
        }

        return dat.ToArray();
    }

    public void UpdateEnemy(Enemy enemy)
    {
        _enemy = enemy;
    }

    public void Death(RealmTime time) {
        if (Corpse == null) 
            return;
        
        Corpse.Parent = this;
    }
        
    public void TransferData(DamageCounter dc)
    {
        dc.LastProjectile = LastProjectile;
        dc.LastHitter = LastHitter;

        foreach (var plr in hitters.Keys)
        {
            if (!hitters.TryGetValue(plr, out var totalDmg))
                totalDmg = 0;
            if (!dc.hitters.TryGetValue(plr, out var totalExistingDmg))
                totalExistingDmg = 0;

            dc.hitters[plr] = totalDmg + totalExistingDmg;
        }
    }
}