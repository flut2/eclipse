using System;
using System.Collections.Generic;
using System.Linq;
using System.Runtime.InteropServices.ComTypes;
using System.Xml.Linq;
using Shared.terrain;
using NLog;
using Dynamitey.Internal.Optimization;
using System.Xml.XPath;

namespace Shared.resources; 

public class ConditionEffect
{
    public ConditionEffectIndex Effect;
    public int DurationMS;
    public float Range;

    public ConditionEffect()
    {
    }

    public ConditionEffect(XElement e)
    {
        Effect = Utils.GetEffect(e.Value);
        DurationMS = (int)(e.GetAttribute<float>("duration") * 1000);
        Range = e.GetAttribute<float>("range");
    }
}

public class ProjectileDesc
{
    public readonly int BulletType;
    public readonly string ObjectId;
    public readonly float LifetimeMS;
    public readonly float Speed;
    public readonly int Size;
    public readonly int Damage;
    public readonly int MagicDamage;
    public readonly int TrueDamage;

    public readonly bool MultiHit;
    public readonly bool PassesCover;
    public readonly bool Parametric;
    public readonly bool Boomerang;
    public readonly bool ParticleTrail;
    public readonly bool Wavy;

    public readonly ConditionEffect[] Effects;

    public readonly float Amplitude;
    public readonly float Frequency;
    public readonly float Magnitude;

    public readonly float Acceleration;
    public readonly float MSPerAcceleration;
    public readonly float SpeedCap;

    public ProjectileDesc(XElement e)
    {
        BulletType = e.GetAttribute<int>("id");
        ObjectId = e.GetValue<string>("ObjectId");
        LifetimeMS = e.GetValue<float>("LifetimeMS");
        Speed = e.GetValue<float>("Speed", 100);
        Size = e.GetAttribute("Size", 100);

        var dmg = e.Element("Damage");
        if (dmg != null)
            Damage = e.GetValue<int>("Damage");
        
        var magicDmg = e.Element("MagicDamage");
        if (magicDmg != null)
            MagicDamage = e.GetValue<int>("MagicDamage");
        
        var trueDmg = e.Element("TrueDamage");
        if (trueDmg != null)
            TrueDamage = e.GetValue<int>("TrueDamage");

        List<ConditionEffect> effects = new();
        foreach (var i in e.Elements("ConditionEffect"))
            effects.Add(new ConditionEffect(i));
        Effects = effects.ToArray();

        MultiHit = e.HasElement("MultiHit");
        PassesCover = e.HasElement("PassesCover");
        Wavy = e.HasElement("Wavy");
        Parametric = e.HasElement("Parametric");
        Boomerang = e.HasElement("Boomerang");
        ParticleTrail = e.HasElement("ParticleTrail");

        Amplitude = e.GetValue<float>("Amplitude", 0);
        Frequency = e.GetValue<float>("Frequency", 1);
        Magnitude = e.GetValue<float>("Magnitude", 3);

        Acceleration = e.ParseFloat("Acceleration");
        MSPerAcceleration = e.ParseFloat("MSPerAcceleration", 50);
        SpeedCap = e.ParseFloat("SpeedCap", Speed + Acceleration * 10);
    }
}

public class ActivateEffect
{
    public readonly ActivateEffects Effect;
    public readonly int Stats;
    public readonly float Amount;
    public readonly float Range;
    public readonly float DurationSec;
    public readonly int DurationMS;
    public readonly ConditionEffectIndex? ConditionEffect;
    public readonly float EffectDuration;
    public readonly int MaximumDistance;
    public readonly float Radius;
    public readonly int TotalDamage;
    public readonly string ObjectId;
    public readonly string Id;
    public readonly string DungeonName;
    public readonly string LockedName;
    public readonly uint Color;
    public readonly ushort SkinType;
    public readonly int Size;
    public readonly bool NoStack;
    public readonly string Target;
    public readonly string Center;
    public readonly int VisualEffect;
    public readonly double ThrowTime;
    public readonly int ImpactDamage;

    public readonly int[] BoostValues;
    public readonly int[] BoostValuesStats;
    public readonly string[] BoostValuesStatsString;

    public readonly string[] ConditionEffects;
    public readonly string StatName;
        
    public ActivateEffect(XElement e)
    {
        Effect = (ActivateEffects)Enum.Parse(typeof(ActivateEffects), e.Value);

        StatName = e.GetAttribute<string>("stat");
        Stats = StatUtils.StatNameToId(StatName);

        if (e.HasAttribute("statId"))
            Stats = e.GetAttribute<int>("statId");

        Amount = e.GetAttribute<float>("amount");
        Range = e.GetAttribute<float>("range");

        DurationSec = e.GetAttribute<float>("duration");
        DurationMS = (int)(DurationSec * 1000.0f);
        if (e.HasAttribute("duration2"))
            DurationMS = (int)(e.GetAttribute<float>("duration2") * 1000);

        if (e.HasAttribute("effect")) {
            var val = e.GetAttribute<string>("effect");

            if (Utils.TryGetEffect(val, out var r))
                ConditionEffect = r;
        }

        if (e.HasAttribute("condEffect"))
            ConditionEffect = Utils.GetEffect(e.GetAttribute<string>("condEffect"));

        if (e.HasAttribute("checkExistingEffect"))
            Utils.GetEffect(e.GetAttribute<string>("checkExistingEffect"));

        EffectDuration = e.GetAttribute<float>("condDuration");
        MaximumDistance = e.GetAttribute<int>("maxDistance");
        Radius = e.GetAttribute<float>("radius");
        TotalDamage = e.GetAttribute<int>("totalDamage");
        ObjectId = e.GetAttribute<string>("objectId");
        if (e.HasAttribute("objectId2"))
            ObjectId = e.GetAttribute<string>("objectId2");
        Id = e.GetAttribute<string>("id");
        DungeonName = e.GetAttribute<string>("dungeonName");
        LockedName = e.GetAttribute<string>("lockedName");

        if (e.HasAttribute("color"))
        {
            Color = e.GetAttribute<uint>("color", 0xddff00);
        }

        SkinType = e.GetAttribute<ushort>("skinType");
        Size = e.GetAttribute<int>("size");
        NoStack = e.GetAttribute<bool>("noStack");
        Target = e.GetAttribute<string>("target");
        Center = e.GetAttribute<string>("center");
        VisualEffect = e.GetAttribute<int>("visualEffect");
        ThrowTime = (e.GetAttribute("throwTime", 0.8) * 1000);
        ImpactDamage = e.GetAttribute<int>("impactDamage");
        if (e.HasAttribute("boostAmounts"))
            BoostValues = e.GetAttribute<string>("boostAmounts").CommaToArray<int>();
        if (e.HasAttribute("boostStats"))
        {
            BoostValuesStatsString = e.GetAttribute<string>("boostStats").CommaToArray<string>();
            BoostValuesStats = StatUtils.ArrayStatNameToId(BoostValuesStatsString);
        }
            
        if (e.HasAttribute("condEffs"))
            ConditionEffects = e.GetAttribute<string>("condEffs").CommaToArray<string>();
    }
}

public class Setpiece
{
    public readonly string Type;
    public readonly ushort Slot;
    public readonly ushort ItemType;

    public Setpiece(XElement elem)
    {
        Type = elem.Value;
        Slot = elem.GetAttribute<ushort>("slot");
        ItemType = elem.GetAttribute<ushort>("itemtype");
    }
}

public class PortalDesc : ObjectDesc
{
    public readonly int Timeout;
    public readonly bool NexusPortal;
    public readonly bool Locked;

    public PortalDesc(ushort type, XElement e) : base(type, e)
    {
        NexusPortal = e.HasElement("NexusPortal");
        Locked = e.HasElement("LockedPortal");
        Timeout = e.GetValue("Timeout", 30);
    }
}

public class Item
{
    public readonly ushort ObjectType;
    public readonly string ObjectId;
    public readonly int SlotType;
    public readonly string Tier;
    public readonly string Description;
    public readonly float RateOfFire;
    public readonly bool Usable;
    public readonly int BagType;
    public readonly int MpCost;
    public readonly int XpBonus;
    public readonly int NumProjectiles;
    public readonly float ArcGap;
    public readonly bool Consumable;
    public readonly bool Potion;
    public readonly string DisplayId;
    public readonly string DisplayName;
    public readonly bool Untradable;
    public readonly float Cooldown;
    public readonly bool Resurrects;
    public readonly int Texture1;
    public readonly int Texture2;

    public readonly string Power;
    public readonly int HpCost;

    public readonly KeyValuePair<int, int>[] StatsBoost;
    public readonly KeyValuePair<int, float>[] StatsBoostPerc;
    public readonly ActivateEffect[] ActivateEffects;
    public readonly ProjectileDesc[] Projectiles;
    public Item(ushort type, XElement e)
    {
        ObjectType = type;
        ObjectId = e.GetAttribute<string>("id");
        SlotType = e.GetValue<int>("SlotType");
        if (e.HasElement("Tier"))
            Tier = e.GetValue<string>("Tier");
        Description = e.GetValue<string>("Description");
        RateOfFire = e.GetValue<float>("RateOfFire", 1);
        Usable = e.HasElement("Usable");
        BagType = e.GetValue<int>("BagType");
        MpCost = e.GetValue<int>("MpCost");
        XpBonus = e.GetValue<int>("XpBonus");
        NumProjectiles = e.GetValue("NumProjectiles", 1);
        ArcGap = e.GetValue("ArcGap", 11.25f);
        Consumable = e.HasElement("Consumable");
        Potion = e.HasElement("Potion");
        DisplayId = e.GetValue<string>("DisplayId");
        DisplayName = string.IsNullOrWhiteSpace(DisplayId) ? ObjectId : DisplayId;
        Untradable = e.HasElement("Untradable");
        Cooldown = e.GetValue("Cooldown", 0.5f);
        Resurrects = e.HasElement("Resurrects");
        Texture1 = e.GetValue<int>("Tex1");
        Texture2 = e.GetValue<int>("Tex2");
        Power = e.GetValue<string>("Power");
        HpCost = e.GetValue<int>("HpCost");

        var stats = new List<KeyValuePair<int, int>>();
        foreach (var i in e.Elements("ActivateOnEquip"))
        {
            var statName = i.GetAttribute<string>("stat");
            var stat = StatUtils.StatNameToId(statName);

            if (i.HasAttribute("statId"))
                stat = i.GetAttribute<int>("statId");

            stats.Add(new KeyValuePair<int, int>(
                stat, i.GetAttribute<int>("amount")));
        }

        StatsBoost = stats.ToArray();
            
        var statsPerc = new List<KeyValuePair<int, float>>();
        foreach (var i in e.Elements("ActivateOnEquipPerc"))
        {
            var statName = i.GetAttribute<string>("stat");
            var stat = StatUtils.StatNameToId(statName);

            if (i.HasAttribute("statId"))
                stat = i.GetAttribute<int>("statId");

            statsPerc.Add(new KeyValuePair<int, float>(
                stat, i.GetAttribute<float>("amount")));
        }

        StatsBoostPerc = statsPerc.ToArray();

        var activate = new List<ActivateEffect>();
        foreach (var i in e.Elements("Activate"))
            activate.Add(new ActivateEffect(i));
        ActivateEffects = activate.ToArray();

        var projs = new List<ProjectileDesc>();
        foreach (var i in e.Elements("Projectile"))
            projs.Add(new ProjectileDesc(i));
        Projectiles = projs.ToArray();
    }
}
    
public class EquipmentSetDesc
{
    public ushort Type { get; private set; }
    public string Id { get; private set; }

    public ActivateEffect[] ActivateOnEquipAll { get; private set; }
    public Setpiece[] Setpieces { get; private set; }

    public static EquipmentSetDesc FromElem(ushort type, XElement setElem, out ushort skinType)
    {
        skinType = 0;

        var activate = new List<ActivateEffect>();
        foreach (var i in setElem.Elements("ActivateOnEquipAll"))
        {
            var ae = new ActivateEffect(i);
            activate.Add(ae);

            if (ae.SkinType != 0)
                skinType = ae.SkinType;
        }

        var setpiece = new List<Setpiece>();
        foreach (var i in setElem.Elements("Setpiece"))
            setpiece.Add(new Setpiece(i));

        var eqSet = new EquipmentSetDesc();
        eqSet.Type = type;
        eqSet.Id = setElem.GetAttribute<string>("id");
        eqSet.ActivateOnEquipAll = activate.ToArray();
        eqSet.Setpieces = setpiece.ToArray();

        return eqSet;
    }
}

public class SkinDesc
{
    public ushort Type { get; private set; }
    public ObjectDesc ObjDesc { get; private set; }

    public ushort PlayerClassType { get; private set; }
    public ushort UnlockLevel { get; private set; }
    public bool Restricted { get; private set; }
    public bool Expires { get; private set; }
    public int Cost { get; private set; }
    public bool UnlockSpecial { get; private set; }
    public bool NoSkinSelect { get; private set; }
    public int Size { get; private set; }
    public string PlayerExclusive { get; private set; }

    public static SkinDesc FromElem(ushort type, XElement skinElem)
    {
        var pct = skinElem.Element("PlayerClassType");
        if (pct == null) return null;

        var sd = new SkinDesc();
        sd.Type = type;
        sd.ObjDesc = new ObjectDesc(type, skinElem);
        sd.PlayerClassType = (ushort)Utils.FromString(pct.Value);
        sd.Restricted = skinElem.HasElement("Restricted");
        sd.Expires = skinElem.HasElement("Expires");
        sd.UnlockSpecial = skinElem.HasElement("UnlockSpecial");
        sd.NoSkinSelect = skinElem.HasElement("NoSkinSelect");
        sd.PlayerExclusive = skinElem.GetValue<string>("PlayerExclusive");

        var ul = skinElem.Element("UnlockLevel");
        if (ul != null) sd.UnlockLevel = ushort.Parse(ul.Value);
        sd.Cost = skinElem.GetValue("Cost", 1000);
        sd.Size = skinElem.GetAttribute("size", 100);

        return sd;
    }
}

public class SpawnCount
{
    public readonly int Mean;
    public readonly int StdDev;
    public readonly int Min;
    public readonly int Max;

    public SpawnCount(XElement elem)
    {
        Mean = elem.GetValue<int>("Mean");
        StdDev = elem.GetValue<int>("StdDev");
        Min = elem.GetValue<int>("Min");
        Max = elem.GetValue<int>("Max");
    }
}

public class UnlockClass
{
    public readonly ushort? Type;
    public readonly ushort? Level;
    public readonly uint? Cost;

    public UnlockClass(XElement e)
    {
        var n = e.Element("UnlockLevel");
        if (n != null && n.HasAttribute("type") && n.HasAttribute("level"))
        {
            Type = n.GetAttribute<ushort>("type");
            Level = n.GetAttribute<ushort>("level");
        }

        n = e.Element("UnlockCost");
        if (n != null)
        {
            Cost = (uint)int.Parse(n.Value);
        }
    }
}

public class Stat
{
    public readonly string Type;
    public readonly int[] MaxValues;
    public readonly int StartingValue;

    public Stat(int index, XElement e)
    {
        Type = StatIndexToName(index);
        var x = e.Element(Type);
        if (x == null)
            return;
            
        StartingValue = int.Parse(x.Value);
        // wack todo
        MaxValues = new int[2];
        MaxValues[0] = x.GetAttribute<int>("t1");
        MaxValues[1] = x.GetAttribute<int>("t2");
    }

    private static string StatIndexToName(int index)
    {
        switch (index)
        {
            case 0: return "Health";
            case 1: return "Mana";
            case 2: return "Strength";
            case 3: return "Wit";
            case 4: return "Defense";
            case 5: return "Resistance";
            case 6: return "Speed";
            case 7: return "Stamina";
            case 8: return "Intelligence";
            case 9: return "Penetration";
            case 10: return "Piercing";
            case 11: return "Haste";
            case 12: return "Tenacity";
        }

        return null;
    }
}

public enum AbilityType : short
{
    Unknown = -1,
    AnomalousBurst = 0,
    ParadoxicalShift = 1,
    Swarm = 2,
    Shapeshift = 3,
    TimeDilation = 4,
    Rewind = 5,
    NullPulse = 6,
    TimeLock = 7
}

public enum AbilitySlotType : byte
{
    Ability1 = 0,
    Ability2 = 1,
    Ability3 = 2,
    Ultimate = 3
}

public class AbilityDesc
{
    public readonly AbilityType AbilityType;
    public readonly int ManaCost;
    public readonly int HealthCost;
    public readonly int CooldownMS;

    public AbilityDesc(XElement e)
    {
        AbilityType = (AbilityType)Enum.Parse(typeof(AbilityType), e.GetValue("Name", "Unknown").Replace(" ", ""), true);
        ManaCost = e.GetValue<int>("ManaCost");
        HealthCost = e.GetValue<int>("HealthCost");
        CooldownMS = e.GetValue<int>("Cooldown") * 1000;
    }
}

public class PlayerDesc : ObjectDesc
{
    public readonly int[] SlotTypes;
    public readonly ushort[] Equipment;
    public readonly Stat[] Stats;
    public readonly UnlockClass Unlock;
    public readonly AbilityDesc[] Abilities;

    public PlayerDesc(ushort type, XElement e) : base(type, e)
    {
        SlotTypes = e.GetValue<string>("SlotTypes").CommaToArray<int>();
        Equipment = e.GetValue<string>("Equipment").CommaToArray<ushort>();
        Stats = new Stat[13];
        for (var i = 0; i < Stats.Length; i++)
            Stats[i] = new Stat(i, e);
        if (e.HasElement("UnlockLevel") || e.HasElement("UnlockCost"))
            Unlock = new UnlockClass(e);

        Abilities = new AbilityDesc[]
        {
            new(e.Element("Ability1")),
            new(e.Element("Ability2")),
            new(e.Element("Ability3")),
            new(e.Element("UltimateAbility"))
        };
    }
}

public class ObjectDesc
{
    public readonly ushort ObjectType;
    public readonly string ObjectId;
    public readonly string DisplayId;
    public readonly string DungeonName;
    public readonly string Group;
    public readonly string Class;
    public readonly bool Character;
    public readonly bool Player;
    public readonly bool Enemy;
    public readonly bool OccupySquare;
    public readonly bool FullOccupy;
    public readonly bool EnemyOccupySquare;
    public readonly bool Static;
    public readonly bool BlocksSight;
    public readonly bool NoMiniMap;
    public readonly bool ProtectFromGroundDamage;
    public readonly bool ProtectFromSink;
    public readonly bool Flying;
    public readonly bool ShowName;
    public readonly bool DontFaceAttacks;
    public readonly int MinSize;
    public readonly int MaxSize;
    public readonly int SizeStep;
    public readonly ProjectileDesc[] Projectiles;
    public readonly int MaxHP;
    public readonly int Defense;
    public readonly int Resistance;
    public readonly int Tenacity;
    public readonly int Agility;
    public readonly bool Quest;
    public readonly bool StasisImmune;
    public readonly bool Restricted;

    public readonly bool KeepMinimap;
    public readonly bool Invulnerable;

    public ObjectDesc(ushort type, XElement e)
    {
        ObjectType = type;
        ObjectId = e.GetAttribute<string>("id");
        DisplayId = e.GetValue<string>("DisplayId");
        if (string.IsNullOrEmpty(DisplayId))
            DisplayId = ObjectId;
        Class = e.GetValue<string>("Class");
        Static = e.HasElement("Static");
        OccupySquare = e.HasElement("OccupySquare");
        FullOccupy = e.HasElement("FullOccupy");
        EnemyOccupySquare = e.HasElement("EnemyOccupySquare");
        BlocksSight = e.HasElement("BlocksSight") || Class == "Wall";
        Enemy = e.HasElement("Enemy");
        MaxHP = e.GetValue<int>("Health");
        Defense = e.GetValue<int>("Defense");
        Resistance = e.GetValue<int>("Resistance");
        Tenacity = e.GetValue<int>("Tenacity");
        Agility = e.GetValue("Agility", 50);
        Group = e.GetValue<string>("Group");
        DungeonName = e.GetValue<string>("DungeonName");
        Character = Class.Equals("Character");
        Player = e.HasElement("Player");
        NoMiniMap = e.HasElement("NoMiniMap");
        ProtectFromGroundDamage = e.HasElement("ProtectFromGroundDamage");
        ProtectFromSink = e.HasElement("ProtectFromSink");
        Flying = e.HasElement("Flying");
        ShowName = e.HasElement("ShowName");
        DontFaceAttacks = e.HasElement("DontFaceAttacks");
        Restricted = e.HasElement("Restricted");

        if (e.HasElement("Size"))
        {
            MinSize = MaxSize = e.GetValue<int>("Size");
            SizeStep = 0;
        }
        else
        {
            MinSize = e.GetValue("MinSize", 100);
            MaxSize = e.GetValue("MaxSize", 100);
            SizeStep = e.GetValue("SizeStep", 0);
        }

        var projs = new List<ProjectileDesc>();
        foreach (var i in e.Elements("Projectile"))
            projs.Add(new ProjectileDesc(i));
            
        Projectiles = projs.ToArray();
        Quest = e.HasElement("Quest");

        StasisImmune = e.HasElement("StasisImmune");
        Invulnerable = e.HasElement("Invulnerable");

        KeepMinimap = e.HasElement("KeepMinimap");
    }
}
    
public class TileDesc
{
    public readonly ushort ObjectType;
    public readonly string ObjectId;
    public readonly bool NoWalk;
    public readonly int Damage;
    public readonly float Speed;
    public readonly bool Push;
    public readonly float PushX;
    public readonly float PushY;

    public TileDesc(ushort type, XElement e)
    {
        ObjectType = type;
        ObjectId = e.GetAttribute<string>("id");
        NoWalk = e.HasElement("NoWalk");

        if (e.HasElement("Damage"))
            Damage = e.GetValue<int>("Damage");

        Speed = e.GetValue("Speed", 1.0f);
        Push = e.HasElement("Push");
        if (Push)
        {
            var anim = e.Element("Animate");
            if (anim.HasAttribute("dx"))
                PushX = anim.GetAttribute<float>("dx");
            if (anim.HasAttribute("dy"))
                PushY = anim.GetAttribute<float>("dy");
        }
    }
}

public class MerchantList
{
    private static readonly Logger Log = LogManager.GetCurrentClassLogger();
        
    public readonly TileRegion Region;
    public readonly CurrencyType Currency;
    public readonly List<ISellableItem> Items;

    public MerchantList(XElement e, XmlData gameData)
    {
        // todo fix
        Region = TileRegion.None; //(TileRegion)Enum.Parse(typeof(TileRegion), e.ParseString("@region").Replace(' ', '_'));
        Currency = (CurrencyType)Enum.Parse(typeof(CurrencyType), e.ParseString("@currency"));
        var idToItemType = gameData.IdToItemType;
        Items = new List<ISellableItem>();
        foreach (var i in e.Elements("Item"))
        {
            if (!idToItemType.TryGetValue(i.Value, out var item))
            {
                Log.Error($"Failed when adding \"{i.Value}\" to shop. Item does not exist.");
                continue;
            }
                
            Items.Add(new MerchantItem(i, item));
        }
    }
}

public class MerchantItem : ISellableItem
{
    public readonly string Name;
    public ushort ItemId { get; }
    public int Price { get; }
    public int Count => -1;

    public MerchantItem(XElement e, ushort type)
    {
        ItemId = type;
        Name = e.Value;
        Price = e.ParseInt("@price");
    }

}

public static class StatUtils
{
    public static int[] ArrayStatNameToId(string[] arr)
    {
        return arr.Select(StatNameToId).ToArray();
    }

    public static int StatNameToId(string stat) {
        return stat switch {
            "MaxHP" => 33,
            "MaxMP" => 34,
            "Strength" => 35,
            "Defense" => 36,
            "Speed" => 37,
            "Stamina" => 38,
            "Penetration" => 39,
            "Wit" => 40,
            "Resistance" => 41,
            "Haste" => 42,
            "Intelligence" => 43,
            "Piercing" => 44,
            "Tenacity" => 45,
            _ => -1
        };
    }
}