using Shared;
using GameServer.realm.entities.player;
using GameServer.realm.worlds;

namespace GameServer.realm.entities; 

public class Portal : StaticObject
{
    public Portal(RealmManager manager, ushort objType, int? life)
        : base(manager, ValidatePortal(manager, objType), life, false, true, false)
    {
        _usable = new SV<bool>(this, StatsType.PortalUsable, true);
        Locked = manager.Resources.GameData.Portals[ObjectType].Locked;
        Opener = "";
    }

    private readonly SV<bool> _usable;
    public bool PlayerOpened { get; set; }
    public string Opener { get; set; }

    public bool Usable
    {
        get => _usable.GetValue();
        set => _usable.SetValue(value);
    }

    public bool Locked { get; private set; }

    public readonly object CreateWorldLock = new();
    public Task CreateWorldTask { get; set; }
    public World WorldInstance { get; set; }
    public event EventHandler<World> WorldInstanceSet;

    private static ushort ValidatePortal(RealmManager manager, ushort objType)
    {
        var portals = manager.Resources.GameData.Portals;
        if (!portals.ContainsKey(objType))
        {
            Log.Warn($"Portal {objType.To4Hex()} does not exist. Using Crown Cove.");
            objType = 0x0706; // default to Crown Cove
        }

        return objType;
    }
        
    protected override void ExportStats(IDictionary<StatsType, object> stats)
    {
        stats[StatsType.PortalUsable] = Usable ? 1 : 0;
        base.ExportStats(stats);
    }

    public override bool HitByProjectile(Projectile projectile, RealmTime time)
    {
        return false;
    }

    public void CreateWorld(Player player)
    {
        World world = null;

        foreach (var p in Program.Resources.Worlds.Data.Values
                     .Where(p => p.portals != null && p.portals.Contains(ObjectType)))
            world = p.id < 0 ? player.Manager.GetWorld(p.id) : player.Manager.AddWorld(new World(p));

        if (world == null)
            return;

        if (PlayerOpened)
        {
            world.PlayerDungeon = true;
            world.Opener = Opener;
            world.Invites = new HashSet<string>();
            world.InviteDict = new Dictionary<string, Player>();
        }

        WorldInstance = world;
        WorldInstanceSet?.Invoke(this, world);
    }
}