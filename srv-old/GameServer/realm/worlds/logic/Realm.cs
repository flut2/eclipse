using System;
using System.Globalization;
using System.Reflection.Metadata.Ecma335;
using System.Runtime.CompilerServices;
using DungeonGenerator.Dungeon;
using GameServer.realm.entities;
using Shared.resources;
using Shared.terrain;

namespace GameServer.realm.worlds.logic;

public class Realm
{
	public enum Biome
	{
		None,
		Volcanic,
		Forest,
		Desert
	}
	
	// todo make this a xml system
	
	private static readonly Dictionary<Biome, List<(string, TileRegion)>> ForestEventList = new()
	{
		{
			Biome.Volcanic, new List<(string, TileRegion)>()
			{
				("Skeletal Skull", TileRegion.Biome_Volacnic_Encounter_Spawn),
				("Hellfire Hydra", TileRegion.Biome_Volacnic_Encounter_Spawn),
				("Blood Elemental", TileRegion.Biome_Volacnic_Encounter_Spawn)
			}
		},
		{
			Biome.Forest, new List<(string, TileRegion)>()
			{
				("Giant Slime", TileRegion.Biome_Forest_Encounter_Spawn),
				("Ethereal Phantom", TileRegion.Biome_Forest_Encounter_Spawn),
				("Woodland Warden", TileRegion.Biome_Forest_Encounter_Spawn)
			}
		},
		{
			Biome.Desert, new List<(string, TileRegion)>()
			{
				("Lamia", TileRegion.Biome_Desert_Encounter_Spawn),
				("Sobek", TileRegion.Biome_Desert_Encounter_Spawn),
				("Rahu", TileRegion.Biome_Desert_Encounter_Spawn)
			}
		}
	};

	private static readonly Dictionary<Biome, string> BiomeToTile = new Dictionary<Biome, string>(3)
	{
		{ Biome.Volcanic, "Cobblestone" },
		{ Biome.Forest, "Grass" },
		{ Biome.Desert, "Desert Sand" },
	};

	private static readonly Dictionary<string, Biome> TileToBiome = new Dictionary<string, Biome>(3)
	{
		{ "Cobblestone", Biome.Volcanic },
		{ "Grass", Biome.Forest },
		{ "Desert Sand", Biome.Desert },
	};

	private static readonly Dictionary<Biome, List<string>> ForestSpawnList = new()
	{
		{ 
			Biome.Volcanic, new List<string>()
			{
				"Imp",
				"Living Flame",
				"Demon Mage",
				"Demon Archer"
			}
		},
		{ 
			Biome.Forest, new List<string>()
			{
				"Goblin Guard",
				"Goblin Grunt",
				"Spike Ball",
				"Crocodile"
			}
		},
		{ 
			Biome.Desert, new List<string>()
			{
				"Jackal Warrior",
				"Jackal Priest",
				"Jackal Archer",
				"Regal Mummy"
			}
		}
	};
	
	public const float EVENT_CHANCE = 0.0005f;
	private const int TIMER_RESET_US = 60 * 1000 * 1000;
	private const int MOB_LIMIT = 30000;

	private World World;
	private long PopulationTimerUs;

	private Dictionary<TileRegion, List<IntPoint>> SpawnableRegions = new();

	public bool EventActive { get; set; }
	public int MobCount { get; set; }

	public Realm(World world)
	{
		World = world;

		SpawnableRegions = new Dictionary<TileRegion, List<IntPoint>>();
		foreach (var region in World.Map.Regions)
		{
			if (!SpawnableRegions.TryGetValue(region.Value, out var points))
				SpawnableRegions[region.Value] = points = new List<IntPoint>();
			points.Add(region.Key);
		}
	}

	public void Tick(RealmTime time)
	{
		PopulationTimerUs -= time.ElapsedUsDelta;
		if (PopulationTimerUs > 0)
			return;
		PopulationTimerUs = TIMER_RESET_US;

		SpawnEvent();
		PopulateRealmMobs();
	}

	public void SpawnEvent()
	{
		if (EventActive)
			return;

		var biome = (Biome)Random.Shared.Next((int)Biome.None, (int)Biome.Desert) + 1;
		
		var chosenEventList = ForestEventList[biome];
		var (chosenEvent, chosenRegion) = chosenEventList[Random.Shared.Next(chosenEventList.Count)];
		var spawns = SpawnableRegions[chosenRegion];
		var chosenPoint = spawns[Random.Shared.Next(spawns.Count)];

		var entity = Entity.Resolve(World.Manager, chosenEvent);
		if (entity == null)
			return;
		
		(entity as Enemy).RealmEvent = true;
		EventActive = true;
		entity.Move(chosenPoint.X + 0.5f, chosenPoint.Y + 0.5f);
		World.EnterWorld(entity);
		World.WorldAnnouncement("A " + entity.ObjectDesc.DisplayId + " has appeared somewhere...");
	}

	private void PopulateRealmMobs()
	{
		var i = 0;
		while (MobCount < MOB_LIMIT)
		{
			var px = 0;
			var py = 0;

			MapTile? mapTile = null;
			do
			{
				px = Random.Shared.Next(World.Map.Width);
				py = Random.Shared.Next(World.Map.Height);
			} while (!ValidateTile(px, py, tile =>
			         {
				         if (tile.ObjDesc != null)
					         return false;
				         if (tile.TileDesc.NoWalk)
					         return false;
				         mapTile = tile;
				         return true;
			         }));

			if (mapTile == null || !TileToBiome.TryGetValue(mapTile.TileDesc.ObjectId, out var biome))
				continue;

			var spawnList = ForestSpawnList[biome];
			var chosen = spawnList[Random.Shared.Next(spawnList.Count)];
			
			var entity = Entity.Resolve(World.Manager, chosen);
			if (entity == null)
				continue;
		
			(entity as Enemy).RealmSpawn = true;
			EventActive = true;
			entity.Move(px + 0.5f, py + 0.5f);
			World.EnterWorld(entity);
		
			MobCount++;
			i++;
		}
	}

	private bool ValidateTile(int x, int y, Predicate<MapTile> func)
	{
		return func(World.Map[x, y]);
	}

	public void OnDeath(Enemy enemy)
	{
		if (enemy.RealmEvent)
			EventActive = false;
		
		if (enemy.RealmSpawn) {
			MobCount--;
			if (Random.Shared.NextDouble() <= EVENT_CHANCE)
				SpawnEvent();
		}
	}
}
