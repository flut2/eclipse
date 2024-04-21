using System.Xml.Linq;
using Shared;
using GameServer.realm;
using GameServer.realm.entities;
using GameServer.realm.entities.player;
using NLog;

namespace GameServer.logic.loot; 

public interface ILootDef
{
    void Populate(RealmManager manager, Enemy enemy, Tuple<Player, int> playerDat,
        Random rand, IList<LootDef> lootDefs);
}

internal class MostDamagers : ILootDef
{
    private readonly ILootDef[] _loots;
    private readonly int _amount;

    public MostDamagers(XElement e, ILootDef[] loots)
    {
        _amount = e.ParseInt("@amount");
        _loots = loots;
    }
        
    public MostDamagers(int amount, params ILootDef[] loots)
    {
        _amount = amount;
        _loots = loots;
    }

    public void Populate(RealmManager manager, Enemy enemy, Tuple<Player, int> playerDat, Random rand,
        IList<LootDef> lootDefs)
    {
        var data = enemy.DamageCounter.GetPlayerData();
        var mostDamage = GetMostDamage(data);
        foreach (var loot in mostDamage.Where(pl => pl.Equals(playerDat)).SelectMany(_ => _loots))
        {
            if (loot is GoldDrop)
            {
                loot.Populate(manager, enemy, playerDat, rand, lootDefs);
                continue;
            }

            loot.Populate(manager, enemy, null, rand, lootDefs);
        }
    }

    private IEnumerable<Tuple<Player, int>> GetMostDamage(IEnumerable<Tuple<Player, int>> data)
    {
        var enumerable = data.ToList();
        var damages = enumerable.Select(_ => _.Item2).ToList();
        var len = damages.Count < _amount ? damages.Count : _amount;
        for (var i = 0; i < len; i++)
        {
            var val = damages.Max();
            yield return enumerable.FirstOrDefault(_ => _.Item2 == val);
            damages.Remove(val);
        }
    }
}

public class Threshold : ILootDef
{
    private readonly double _threshold;
    private readonly ILootDef[] _children;

        
    public Threshold(XElement e, ILootDef[] loots)
    {
        _threshold = e.ParseFloat("@amount");
        _children = loots;
    }
        
    public Threshold(double threshold, params ILootDef[] children)
    {
        _threshold = threshold;
        _children = children;
    }

    public void Populate(RealmManager manager, Enemy enemy, Tuple<Player, int> playerDat,
        Random rand, IList<LootDef> lootDefs)
    {
        if (playerDat == null || playerDat.Item2 / (double)enemy.MaximumHP <= _threshold)
        {
            return;
        }

        foreach (var i in _children)
        {
            if (i is GoldDrop)
            {
                i.Populate(manager, enemy, playerDat, rand, lootDefs);
                continue;
            }

            i.Populate(manager, enemy, null, rand, lootDefs);
        }
    }
}

public class TierLoot : ILootDef
{
    public static readonly int[] WeaponT = { 1, 2, 3, 8, 17, 24 };

    // old: 20 trap, 21 orb, 22 prism
    public static readonly int[] AbilityT = { 4, 5, 11, 12, 13, 15, 16, 18, 19, 23, 27, 28, 29, 30 };
    public static readonly int[] ArmorT = { 6, 7, 14 };
    public static readonly int[] RingT = { 9 };
    public static readonly int[] PotionT = { 10 };
    public static readonly int[] ArtifactT = { 31 };
    public static readonly int[] CharmT = { 32 };

    private readonly string _tier;
    private readonly int[] _types;
    private readonly double _probability;

    public TierLoot(XElement e)
    {
        _tier = e.ParseString("@tier");
        switch (e.ParseString("@type"))
        {
            case "Weapon":
                _types = WeaponT;
                break;
            case "Ability":
                _types = AbilityT;
                break;
            case "Armor":
                _types = ArmorT;
                break;
            case "Ring":
                _types = RingT;
                break;
            case "Potion":
                _types = PotionT;
                break;
            default:
                throw new NotSupportedException(e.ParseString("@type"));
        }
            
        _probability = e.ParseFloat("@probability");
    }
        
    public TierLoot(string tier, ItemType type, double probability)
    {
        _tier = tier;
        switch (type)
        {
            case ItemType.Weapon:
                _types = WeaponT;
                break;
            case ItemType.Ability:
                _types = AbilityT;
                break;
            case ItemType.Armor:
                _types = ArmorT;
                break;
            case ItemType.Ring:
                _types = RingT;
                break;
            case ItemType.Potion:
                _types = PotionT;
                break;
            default:
                throw new NotSupportedException(type.ToString());
        }

        _probability = probability;
    }

    public void Populate(RealmManager manager, Enemy enemy, Tuple<Player, int> playerDat,
        Random rand, IList<LootDef> lootDefs)
    {
        if (playerDat != null) return;
        var candidates = manager.Resources.GameData.Items
            .Where(item => Array.IndexOf(_types, item.Value.SlotType) != -1 
                           && item.Value.Tier == _tier)
            .Select(item => item.Value)
            .ToArray();
        foreach (var i in candidates)
            lootDefs.Add(new LootDef(i, _probability / candidates.Length));
    }
}

public class ItemLoot : ILootDef
{
    protected static readonly Logger Log = LogManager.GetLogger("ItemLoot");
    private readonly string _item;
    private readonly double _probability;

    public ItemLoot(XElement e)
    {
        _item = e.ParseString("@item");
        _probability = e.ParseFloat("@probability");
    }
        
    public ItemLoot(string item, double probability)
    {
        _item = item;
        _probability = probability;

        // Send items for the gameserver to log any non-existent items on BehaviorDb startup.
        BehaviorDb.SendItem(item);
    }

    public void Populate(RealmManager manager, Enemy enemy, Tuple<Player, int> playerDat,
        Random rand, IList<LootDef> lootDefs)
    {
        if (playerDat != null) return;
        var dat = manager.Resources.GameData;

        var objType = dat.IdToObjectType[_item];
        if (dat.IdToObjectType.ContainsKey(_item)
            && dat.Items.ContainsKey(objType))
        {
            lootDefs.Add(new LootDef(dat.Items[objType], _probability));
        }
    }
}
public class GoldDrop : ILootDef
{
    private readonly int _min;
    private readonly int _max;
    private readonly double _probability;

    public GoldDrop(XElement e)
    {
        _min = e.ParseInt("@min");
        var max = e.ParseInt("@max");
        _max = max <= _min ? _min : max;
        _probability = e.ParseFloat("@probability");
    }
        
    public GoldDrop(int min, int max = 0, double probability = 1)
    {
        _min = min;
        _max = max <= 0 ? min : max;
        _probability = probability;
    }

    public void Populate(RealmManager manager, Enemy enemy, Tuple<Player, int> playerDat,
        Random rand, IList<LootDef> lootDefs)
    {
        if (playerDat == null)
            return;
        if (_probability < MathUtils.NextDouble())
            return;
        var player = playerDat.Item1;
        player.Client.Account.Credits = player.Credits += MathUtils.Next(_min, _max);
        player.Client.SendShowEffect(EffectType.Flow, player.Id, enemy.X, enemy.Y, enemy.X, enemy.Y, 0xFFFF00);
    }
}