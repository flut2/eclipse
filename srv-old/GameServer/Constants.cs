using Shared;

namespace GameServer; 

public static class Constants {
    public static readonly float? GlobalLootBoost = 1f;
    public static readonly DateTime EventEnds = new(2021, 12, 01);

    public static readonly ConditionEffectIndex[] NegativeEffsIdx = {
        ConditionEffectIndex.Bleeding, ConditionEffectIndex.Sick,
    };
}