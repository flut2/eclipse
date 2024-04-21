namespace GameServer.realm; 

public enum StatsType : byte
{
    HP = 0,
    Size = 1,
    MP = 2,
    Inv0 = 3,
    Inv1 = 4,
    Inv2 = 5,
    Inv3 = 6,
    Inv4 = 7,
    Inv5 = 8,
    Inv6 = 9,
    Inv7 = 10,
    Inv8 = 11,
    Inv9 = 12,
    Inv10 = 13,
    Inv11 = 14,
    Inv12 = 15,
    Inv13 = 16,
    Inv14 = 17,
    Inv15 = 18,
    Inv16 = 19,
    Inv17 = 20,
    Inv18 = 21,
    Inv19 = 22,
    Inv20 = 23,
    Inv21 = 24,
    Name = 25,
    MerchType = 26,
    MerchPrice = 27,
    MerchCount = 28,
    Gems = 29,
    Gold = 30,
    Crowns = 31,
    OwnerAccountId = 32,

    MaxHP = 33,
    MaxMP = 34,
    Strength = 35,
    Defense = 36,
    Speed = 37,
    Stamina = 38,
    Wit = 39,
    Resistance = 40,
    Intelligence = 41,
    Penetration = 42,
    Piercing = 43,
    Haste = 44,
    Tenacity = 45,

    HPBonus = 46,
    MPBonus = 47,
    StrengthBonus = 48,
    DefenseBonus = 49,
    SpeedBonus = 50,
    StaminaBonus = 51,
    WitBonus = 52,
    ResistanceBonus = 53,
    IntelligenceBonus = 54,
    PenetrationBonus = 55,
    PiercingBonus = 56,
    HasteBonus = 57,
    TenacityBonus = 58,

    Condition = 59,
    Texture1 = 60,
    Texture2 = 61,
    SellablePrice = 62,
    PortalUsable = 63,
    AccountId = 64,
    Tier = 65,
    DamageMultiplier = 66,
    HitMultiplier = 67,
    AltTextureIndex = 69,
    Guild = 70,
    GuildRank = 71,
    Texture = 72,
    None = byte.MaxValue
}

public class SV<T>
{
    private readonly Entity _owner;
    private readonly StatsType _type;
    private readonly bool _updateSelfOnly;
    private readonly Func<T, T> _transform;
    private T _value;
    private T _tValue;

    public SV(Entity e, StatsType type, T value, bool updateSelfOnly = false, Func<T, T> transform = null)
    {
        _owner = e;
        _type = type;
        _updateSelfOnly = updateSelfOnly;
        _transform = transform;

        _value = value;
        _tValue = Transform(value);
    }

    public T GetValue()
    {
        return _value;
    }

    public void SetValue(T value)
    {
        if (_value != null && _value.Equals(value))
            return;
        _value = value;

        var tVal = Transform(value);
        if (_tValue != null && _tValue.Equals(tVal))
            return;
        _tValue = tVal;

        _owner.InvokeStatChange(_type, tVal, _updateSelfOnly);
    }

    public override string ToString()
    {
        return _value.ToString();
    }

    private T Transform(T value)
    {
        return _transform == null ? value : _transform(value);
    }
}

public class StatChangedEventArgs : EventArgs
{
    public StatChangedEventArgs(StatsType stat, object value, bool updateSelfOnly = false)
    {
        Stat = stat;
        Value = value;
        UpdateSelfOnly = updateSelfOnly;
    }

    public StatsType Stat { get; private set; }
    public object Value { get; private set; }
    public bool UpdateSelfOnly { get; private set; }
}
