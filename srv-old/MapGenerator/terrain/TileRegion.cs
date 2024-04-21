namespace terrain
{
    public enum TileRegion : byte
    {
        Spawn = 1,

        Biome_Desert_Encounter_Spawn = 41,
        Biome_Volcanic_Encounter_Spawn = 42,
        Biome_Forest_Encounter_Spawn = 43,

        Biome_Desert_Setpiece_Spawn = 44,
        Biome_Volcanic_Setpiece_Spawn = 45,
        Biome_Forest_Setpiece_Spawn = 46,

        FM_Empty = byte.MaxValue
    }
}
