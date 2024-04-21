using GameServer.realm.entities.player;
using GameServer.realm.worlds;
using Shared;
using wServer.realm;
namespace GameServer.realm;

public class StatsManager 
{
    public const byte STAT_TOTAL_COUNT = 13;
    public const byte HEALTH_STAT = 0;
    public const byte MANA_STAT = 1;
    public const byte STRENGTH_STAT = 2;
    public const byte WIT_STAT = 3;
    public const byte DEFENSE_STAT = 4;
    public const byte RESISTANCE_STAT = 5;
    public const byte SPEED_STAT = 6;
    public const byte STAMINA_STAT = 7;
    public const byte INTELLIGENCE_STAT = 8;
    public const byte PENETRATION_STAT = 9;
    public const byte PIERCING_STAT = 10;
    public const byte HASTE_STAT = 11;
    public const byte TENACITY_STAT = 12;

    internal readonly Player Owner;
    internal readonly BaseStatManager Base;
    internal readonly BoostStatManager Boost;

    private readonly SV<short>[] _stats;

    public int this[int index] => Base[index] + Boost[index];

    public StatsManager(Player owner) 
    {
        Owner = owner;
        Base = new BaseStatManager(this);
        Boost = new BoostStatManager(this);

        _stats = new SV<short>[STAT_TOTAL_COUNT];
        for (var i = 0; i < STAT_TOTAL_COUNT; i++)
            _stats[i] = new SV<short>(Owner, GetStatType(i), (short) this[i], i != HEALTH_STAT && i != MANA_STAT); // make maxHP and maxMP global update
    }

    public void ReCalculateValues(InventoryChangedEventArgs e = null) {
        Base.ReCalculateValues(e);
        Boost.ReCalculateValues(e);

        for (var i = 0; i < _stats.Length; i++)
            _stats[i].SetValue((short) this[i]);
    }

    internal void StatChanged(int index) {
        _stats[index].SetValue((short) this[index]);
    }

    public static float GetPhysDamage(Entity host, int damage, Player hitter) {
        damage = (int) (damage * hitter.DamageMultiplier);
        var limit = damage * 0.25f;
        int def;
        if (host is Player p)
            def = p.Stats[STRENGTH_STAT];
        else {
            if (hitter == null)
                return 0;

            var desc = host.ObjectDesc;
            def = desc.Defense;

            if (host.HasConditionEffect(ConditionEffects.Armored))
                def = (int) (def * 1.25);
        }


        var penetration = hitter.Stats[PENETRATION_STAT];
        float ret = damage - (def - penetration);
        if (ret < limit)
            ret = limit;

        if (host.HasConditionEffect(ConditionEffects.Invulnerable))
            ret = 0;

        return ret;
    }

    public static float GetMagicDamage(Entity host, int damage, Player hitter) {
        damage = (int) (damage * hitter.DamageMultiplier);
        var limit = damage * 0.25f;
        int res;
        if (host is Player p)
            res = p.Stats[WIT_STAT];
        else {
            if (hitter == null)
                return 0;

            res = host.ObjectDesc.Resistance;
        }


        var piercing = hitter.Stats[PIERCING_STAT];
        float ret = damage - (res - piercing);
        if (ret < limit)
            ret = limit;

        if (host.HasConditionEffect(ConditionEffects.Invulnerable))
            ret = 0;

        return ret;
    }

    public static float GetTrueDamage(Entity host, int damage, Player hitter) {
        damage = (int) (damage * hitter.DamageMultiplier);
        float ret = damage;

        if (host.HasConditionEffect(ConditionEffects.Invulnerable))
            ret = 0;

        return ret;
    }

    public float GetPhysicalDamage(int damage, Player p) {
        damage = (int) (damage * p.HitMultiplier);
        var limit = damage * 0.25f;

        var def = p.Stats[STRENGTH_STAT];
        if (p.HasConditionEffect(ConditionEffects.Armored))
            def = (int) (def * 1.25);

        float ret = damage - def;
        if (ret < limit)
            ret = limit;

        if (Owner.HasConditionEffect(ConditionEffects.Invulnerable))
            ret = 0;

        return ret;
    }

    public float GetMagicDamage(int damage, Player p) {
        damage = (int) (damage * p.HitMultiplier);
        var limit = damage * 0.25f;

        var res = p.Stats[WIT_STAT];
        float ret = damage - res;
        if (ret < limit)
            ret = limit;

        if (Owner.HasConditionEffect(ConditionEffects.Invulnerable))
            ret = 0;

        return ret;
    }
    
    public float GetTrueDamage(int damage) {
        float ret = damage;
        if (Owner.HasConditionEffect(ConditionEffects.Invulnerable))
            ret = 0;
        return ret;
    }

    public float GetSpeed(MapTile tile) {
        var ret = 4 + 5.6f * (this[SPEED_STAT] / 75f);
        return ret * tile.TileDesc.Speed;
    }

    public float GetHpRegen() {
        var stamina = this[STAMINA_STAT];
        if (Owner.HasConditionEffect(ConditionEffects.Sick))
            stamina = 0;
        return 1 + stamina * .12f;
    }

    public float GetMpRegen() {
        return 0.5f + this[INTELLIGENCE_STAT] * .06f;
    }

    public static int GetStatIndex(StatsType stat) {
        return stat switch {
            StatsType.MaxHP => HEALTH_STAT,
            StatsType.MaxMP => MANA_STAT,
            StatsType.Strength => STRENGTH_STAT,
            StatsType.Wit => WIT_STAT,
            StatsType.Defense => DEFENSE_STAT,
            StatsType.Resistance => RESISTANCE_STAT,
            StatsType.Speed => SPEED_STAT,
            StatsType.Stamina => STAMINA_STAT,
            StatsType.Intelligence => INTELLIGENCE_STAT,
            StatsType.Penetration => PENETRATION_STAT,
            StatsType.Piercing => PIERCING_STAT,
            StatsType.Haste => HASTE_STAT,
            StatsType.Tenacity => TENACITY_STAT,
            _ => -1
        };
    }

    public static StatsType GetStatType(int stat)
    {
        return stat switch
        {
            HEALTH_STAT => StatsType.MaxHP,
            MANA_STAT => StatsType.MaxMP,
            STRENGTH_STAT => StatsType.Strength,
            WIT_STAT => StatsType.Wit,
            DEFENSE_STAT => StatsType.Defense,
            RESISTANCE_STAT => StatsType.Resistance,
            SPEED_STAT => StatsType.Speed,
            STAMINA_STAT => StatsType.Stamina,
            INTELLIGENCE_STAT => StatsType.Intelligence,
            PENETRATION_STAT => StatsType.Penetration,
            PIERCING_STAT => StatsType.Piercing,
            HASTE_STAT => StatsType.Haste,
            TENACITY_STAT => StatsType.Tenacity,
            _ => StatsType.None
        };
    }

    public static StatsType GetStatTypeShort(string stat) {
        return stat switch {
            "HP" => StatsType.MaxHP,
            "MP" => StatsType.MaxMP,
            "STR" => StatsType.Strength,
            "WIT" => StatsType.Wit,
            "DEF" => StatsType.Defense,
            "RES" => StatsType.Resistance,
            "SPD" => StatsType.Speed,
            "STM" => StatsType.Stamina,
            "INT" => StatsType.Intelligence,
            "PEN" => StatsType.Penetration,
            "PRC" => StatsType.Piercing,
            "HST" => StatsType.Haste,
            "TEN" => StatsType.Tenacity,
            _ => StatsType.None
        };
    }

    public static StatsType GetBoostStatType(int stat) {
        return stat switch
        {
            HEALTH_STAT => StatsType.HPBonus,
            MANA_STAT => StatsType.MPBonus,
            STRENGTH_STAT => StatsType.StrengthBonus,
            WIT_STAT => StatsType.WitBonus,
            DEFENSE_STAT => StatsType.DefenseBonus,
            RESISTANCE_STAT => StatsType.ResistanceBonus,
            SPEED_STAT => StatsType.SpeedBonus,
            STAMINA_STAT => StatsType.StaminaBonus,
            INTELLIGENCE_STAT => StatsType.IntelligenceBonus,
            PENETRATION_STAT => StatsType.PenetrationBonus,
            PIERCING_STAT => StatsType.PiercingBonus,
            HASTE_STAT => StatsType.HasteBonus,
            TENACITY_STAT => StatsType.TenacityBonus,
            _ => StatsType.None
        };
    }

    public void ExportStatData(IDictionary<StatsType, object> stats)
    {
        stats[StatsType.MaxHP] = this[HEALTH_STAT];
        stats[StatsType.MaxMP] = this[MANA_STAT];
        stats[StatsType.Strength] = this[STRENGTH_STAT];
        stats[StatsType.Wit] = this[WIT_STAT];
        stats[StatsType.Defense] = this[DEFENSE_STAT];
        stats[StatsType.Resistance] = this[RESISTANCE_STAT];
        stats[StatsType.Speed] = this[SPEED_STAT];
        stats[StatsType.Stamina] = this[STAMINA_STAT];
        stats[StatsType.Intelligence] = this[INTELLIGENCE_STAT];
        stats[StatsType.Penetration] = this[PENETRATION_STAT];
        stats[StatsType.Piercing] = this[PIERCING_STAT];
        stats[StatsType.Haste] = this[HASTE_STAT];
        stats[StatsType.Tenacity] = this[TENACITY_STAT];

        stats[StatsType.HPBonus] = Boost[HEALTH_STAT];
        stats[StatsType.MPBonus] = Boost[MANA_STAT];
        stats[StatsType.StrengthBonus] = Boost[STRENGTH_STAT];
        stats[StatsType.WitBonus] = Boost[WIT_STAT];
        stats[StatsType.DefenseBonus] = Boost[DEFENSE_STAT];
        stats[StatsType.ResistanceBonus] = Boost[RESISTANCE_STAT];
        stats[StatsType.SpeedBonus] = Boost[SPEED_STAT];
        stats[StatsType.StaminaBonus] = Boost[STAMINA_STAT];
        stats[StatsType.IntelligenceBonus] = Boost[INTELLIGENCE_STAT];
        stats[StatsType.PenetrationBonus] = Boost[PENETRATION_STAT];
        stats[StatsType.PiercingBonus] = Boost[PIERCING_STAT];
        stats[StatsType.HasteBonus] = Boost[HASTE_STAT];
        stats[StatsType.TenacityBonus] = Boost[TENACITY_STAT];

    }
}