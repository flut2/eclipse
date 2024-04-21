using System.Xml.Linq;
using Shared;
using wServer.realm;

namespace GameServer.realm.entities; 

public class Container : StaticObject, IContainer
{

    public Container(RealmManager manager, ushort objType, int? life, bool dying, RInventory dbLink = null)
        : base(manager, objType, life, false, dying, false)
    {
        Initialize(dbLink);
    }

    public Container(RealmManager manager, ushort id)
        : base(manager, id, null, false, false, false)
    {
        Initialize(null);
    }

    private void Initialize(RInventory dbLink)
    {
        Inventory = new Inventory(this);
        BagOwners = Array.Empty<int>();
        DbLink = dbLink;

        var node = Manager.Resources.GameData.ObjectTypeToElement[ObjectType];
        SlotTypes = Utils.ResizeArray(node.Element("SlotTypes").Value.CommaToArray<int>(), 9);
        var eq = node.Element("Equipment");
        if (eq != null)
        {
            var inv = eq.Value.CommaToArray<ushort>().Select(_ => _ == ushort.MaxValue ? null : Manager.Resources.GameData.Items[_]).ToArray();
            Array.Resize(ref inv, 9);
            Inventory.SetItems(inv);
        }
    }

    public RInventory DbLink { get; private set; }
    public int[] SlotTypes { get; private set; }
    public Inventory Inventory { get; private set; }
    public int[] BagOwners { get; set; }
        
    protected override void ExportStats(IDictionary<StatsType, object> stats)
    {
        if (Inventory == null) return;
        stats[StatsType.Inv0] = Inventory[0]?.ObjectType ?? ushort.MaxValue;
        stats[StatsType.Inv1] = Inventory[1]?.ObjectType ?? ushort.MaxValue;
        stats[StatsType.Inv2] = Inventory[2]?.ObjectType ?? ushort.MaxValue;
        stats[StatsType.Inv3] = Inventory[3]?.ObjectType ?? ushort.MaxValue;
        stats[StatsType.Inv4] = Inventory[4]?.ObjectType ?? ushort.MaxValue;
        stats[StatsType.Inv5] = Inventory[5]?.ObjectType ?? ushort.MaxValue;
        stats[StatsType.Inv6] = Inventory[6]?.ObjectType ?? ushort.MaxValue;
        stats[StatsType.Inv7] = Inventory[7]?.ObjectType ?? ushort.MaxValue;
        stats[StatsType.Inv8] = Inventory[8]?.ObjectType ?? ushort.MaxValue;
        stats[StatsType.OwnerAccountId] = (BagOwners.Length == 1 ? BagOwners[0] : ushort.MaxValue).ToString();
        base.ExportStats(stats);
    }

    public override void Tick(RealmTime time)
    {
        if (Inventory == null)
            return;

        if (ObjectType == 0x0504) //Vault chest
            return;
            
        if (Inventory.Count(i => i != null && i!.ObjectType != ushort.MaxValue) == 0)
            Owner?.LeaveWorld(this);

        base.Tick(time);
    }

    public override bool HitByProjectile(Projectile projectile, RealmTime time)
    {
        return false;
    }
}