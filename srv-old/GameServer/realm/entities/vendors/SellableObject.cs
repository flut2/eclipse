using System.ComponentModel;
using Shared;
using GameServer.realm.entities.player;
using GameServer.realm.worlds.logic;

namespace GameServer.realm.entities.vendors; 

public enum BuyResult
{
    [Description("Purchase successful.")] Ok,

    [Description("Cannot purchase items with a guest account.")]
    IsGuest,
    [Description("Insufficient Rank.")] InsufficientRank,
    [Description("Insufficient Funds.")] InsufficientFunds,

    [Description("Can't buy items on a test map.")]
    IsTestMap,
    [Description("Uninitalized.")] Uninitialized,
    [Description("Transaction failed.")] TransactionFailed,

    [Description("Item is currently being purchased.")]
    BeingPurchased,

    [Description("Admins can't buy player merched items.")]
    Admin
}

public abstract class SellableObject : StaticObject
{
    protected static Random Rand = new();

    private readonly SV<int> _price;
    private readonly SV<CurrencyType> _currency;

    public int Price
    {
        get => _price.GetValue();
        set => _price.SetValue(value);
    }

    public CurrencyType Currency
    {
        get => _currency.GetValue();
        set => _currency.SetValue(value);
    }

    public int Tax { get; set; }

    protected SellableObject(RealmManager manager, ushort objType)
        : base(manager, objType, null, true, false, false)
    {
        _price = new SV<int>(this, StatsType.SellablePrice, 0);
        _currency = new SV<CurrencyType>(this, StatsType.MerchPrice, 0);
    }

    public virtual void Buy(Player player)
    {
        SendFailed(player, BuyResult.Uninitialized);
    }

    protected override void ExportStats(IDictionary<StatsType, object> stats)
    {
        stats[StatsType.SellablePrice] = Price;
        stats[StatsType.MerchPrice] = (int)Currency;
        base.ExportStats(stats);
    }

    protected BuyResult ValidateCustomer(Player player)
    {
        if (player.GetCurrency(Currency) < Price)
            return BuyResult.InsufficientFunds;
        return BuyResult.Ok;
    }

    protected void SendFailed(Player player, BuyResult result)
    {
        player.Client.SendBuyResult(1, $"Purchase Error: {result.GetDescription()}");
    }
}