using Shared;
using Shared.resources;
using Shared.terrain;
using GameServer.realm.entities;
using GameServer.realm.entities.vendors;
using wServer.realm;

namespace GameServer.realm.worlds.logic; 

public class Stash : World
{
    public int AccountId { get; private set; }

    private readonly Client _client;

    private LinkedList<Container> vaults;

    public Stash(ProtoWorld proto, Client client = null) : base(proto)
    {
        if (client != null)
        {
            _client = client;
            AccountId = _client.Account.AccountId;
            vaults = new LinkedList<Container>();
        }
    }

    public override bool AllowedAccess(Client client)
    {
        return base.AllowedAccess(client) && AccountId == client.Account.AccountId;
    }
    
    protected override void Init()
    {
        if (IsLimbo)
            return;

        FromWorldMap(new MemoryStream(Manager.Resources.Worlds[Name].mapData));
        InitVault();
        InitShops();
    }

    private void InitVault()
    {
        var vaultChestPosition = new List<IntPoint>();
        var spawn = new IntPoint(0, 0);

        var w = Map.Width;
        var h = Map.Height;

        for (var y = 0; y < h; y++)
        for (var x = 0; x < w; x++)
        {
            var tile = Map[x, y];
            switch (tile.Region)
            {
                case TileRegion.Spawn:
                    spawn = new IntPoint(x, y);
                    break;
                case TileRegion.Stash:
                    vaultChestPosition.Add(new IntPoint(x, y));
                    break;
            }
        }

        vaultChestPosition.Sort((x, y) => Comparer<int>.Default.Compare(
            (x.X - spawn.X) * (x.X - spawn.X) + (x.Y - spawn.Y) * (x.Y - spawn.Y),
            (y.X - spawn.X) * (y.X - spawn.X) + (y.Y - spawn.Y) * (y.Y - spawn.Y)));

        Container con;
        for (var i = 0; i < _client.Account.VaultCount && vaultChestPosition.Count > 0; i++)
        {
            var vaultChest = new DbVaultSingle(_client.Account, i);
            con = new Container(_client.Manager, 0x0504, null, false, vaultChest);
            con.BagOwners = new int[] { _client.Account.AccountId };
            con.Inventory.SetItems(vaultChest.Items);
            con.Inventory.InventoryChanged += (sender, e) => SaveChest(((Inventory)sender).Parent);
            con.Move(vaultChestPosition[0].X + 0.5f, vaultChestPosition[0].Y + 0.5f);
            EnterWorld(con);
            vaultChestPosition.RemoveAt(0);
            vaults.AddFirst(con);
        }

        foreach (var i in vaultChestPosition)
        {
            var x = new ClosedVaultChest(_client.Manager, 0x0505);
            x.Move(i.X + 0.5f, i.Y + 0.5f);
            EnterWorld(x);
        }
    }

    public override void Tick(RealmTime time)
    {
        if (vaults != null && vaults.Count > 0)
        {
            foreach (var vault in vaults)
            {
                if (vault?.Inventory == null) 
                    continue;
                
                var items = vault.Inventory.Count(i => i != null && i.ObjectType != ushort.MaxValue) + "/8";
                if (!items.Equals(vault.Name))
                    vault.Name = items;
            }
        }

        base.Tick(time);
    }

    private void SaveChest(IContainer chest)
    {
        var dbLink = chest?.DbLink;
        if (dbLink == null)
            return;

        dbLink.Items = chest.Inventory.GetItemTypes();
        dbLink.FlushAsync();
    }

    public override void LeaveWorld(Entity entity)
    {
        base.LeaveWorld(entity);

        if (entity.ObjectType != 0x0405)
            return;
            
        var x = new StaticObject(_client.Manager, 0x0406, null, true, false, false);
        x.Move(entity.X, entity.Y);
        EnterWorld(x);
    }
}