using System;

namespace Shared.terrain; 

public enum TileRegion : byte
{
    None,
    Spawn,
    Store1,
    Store2,
    Store3,
    Stash,
    Biome_Desert_Encounter_Spawn = 41,
    Biome_Volacnic_Encounter_Spawn = 42,
    Biome_Forest_Encounter_Spawn = 43,
    Biome_Desert_Setpiece_Spawn = 44,
    Biome_Volacnic_Setpiece_Spawn = 45,
    Biome_Forest_Setpiece_Spawn = 46,
    EM_Empty = byte.MaxValue
}