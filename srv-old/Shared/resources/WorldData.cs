using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Linq;
using System.IO;
using System.Text;
using System.Xml.Linq;
using Shared.terrain;
using NLog;
using Newtonsoft.Json;

namespace Shared.resources; 

public struct ProtoWorld
{
    public string name;
    public string sbName;
    public int id;
    public int difficulty;
    public int background;
    public bool isLimbo;
    public bool restrictTp;
    public bool showDisplays;
    public bool persist;
    public int blocking;
    public bool setpiece;
    public int[] portals;
    public string[] music;
    public string map;
    public byte[] mapData;
    public string realm;
    public int bgLightColor;
    public float bgLightIntensity;
    public float dayLightIntensity;
    public float nightLightIntensity;
    public bool quakeIgnore;
}

public class TauntData
{
    public readonly string Name;
    public readonly string[] EnemyCount;
    public readonly string[] Final;
    public readonly string[] Spawn;
    public readonly string[] Death;

    public TauntData(XElement e)
    {
        XElement n;
        Name = e.ParseString("@name");
        if ((n = e.Element("EnemyCount")) != null)
            EnemyCount = n.Elements("Message").Select(x => x.Value).ToArray();

        if ((n = e.Element("Final")) != null)
            Final = n.Elements("Message").Select(x => x.Value).ToArray();
            
        if ((n = e.Element("Spawn")) != null)
            Spawn = n.Elements("Message").Select(x => x.Value).ToArray();
            
        if ((n = e.Element("Death")) != null)
            Death = n.Elements("Message").Select(x => x.Value).ToArray();
    }
}

public class SpawnData
{
    public readonly TileRegion Region;
    public readonly int Divider;
    public readonly List<SpawnInfo> Spawns;

    public SpawnData(XElement e)
    {
        Region = (TileRegion)Enum.Parse(typeof(TileRegion), e.ParseString("@region").Replace(' ', '_'));
        // can't divide by 0 :D
        Divider = e.ParseInt("@divider", 100);
        Spawns = new List<SpawnInfo>();
        foreach (var i in e.Elements("Spawn"))
            Spawns.Add(new SpawnInfo(i));
    }
}

public class SpawnInfo
{
    public readonly string Name;
    public readonly double Chance;
    public SpawnInfo(XElement e)
    {
        Name = e.ParseString("@id");
        Chance = e.ParseFloat("@chance");
    }
}

public class SetpieceData
{
    public readonly TileRegion Region;
    public readonly ProtoWorld Setpiece;
    public readonly int Min;
    public readonly int Max;
    public readonly int[] X;
    public readonly int[] Y;
    public readonly int Size;

    public SetpieceData(XElement e, IDictionary<string, ProtoWorld> worlds)
    {
        Setpiece = worlds[e.ParseString("@setpiece")];
        Region = (TileRegion)Enum.Parse(typeof(TileRegion), e.ParseString("@region").Replace(' ', '_'));
        Min = e.ParseInt("@min");
        Max = e.ParseInt("@max", Min != 0 ? Min + 1 : 1);
        X = e.ParseIntArray("@x", ',');
        Y = e.ParseIntArray("@y", ',');
        Size = e.ParseInt("@size");
    }
}

public class EventData
{
    public readonly string ObjectId;
    public readonly string Setpiece;

    public EventData(XElement e)
    {
        ObjectId = e.Value;
        Setpiece = e.ParseString("@setpiece");
    }
}

public class BiomeData
{
    public readonly TauntData[] TauntData;
    public readonly SpawnData[] SpawnData;
    public readonly SetpieceData[] SetpieceData;
    public readonly EventData[] EventData;
        
    public BiomeData(XElement e, IDictionary<string, ProtoWorld> worlds)
    {
        TauntData = e.Elements("Taunt").Select(x => new TauntData(x)).ToArray();
        SpawnData = e.Elements("Biome").Select(x => new SpawnData(x)).ToArray();
        SetpieceData = e.Elements("Setpiece").Select(x => new SetpieceData(x, worlds)).ToArray();
        EventData = e.Elements("Event").Select(x => new EventData(x)).ToArray();
    }
}

public class WorldData
{
    private static readonly Logger Log = LogManager.GetCurrentClassLogger();

    public readonly IList<string> Setpieces;
    public IDictionary<string, ProtoWorld> Data { get; private set; }
    public IDictionary<string, BiomeData> BiomeData { get; private set; }

    public WorldData(string dir, XmlData gameData)
    {
        Dictionary<string, ProtoWorld> worlds;
        List<string> setpieces;
        Dictionary<string, BiomeData> biomes;
        Data = new ReadOnlyDictionary<string, ProtoWorld>(worlds = new Dictionary<string, ProtoWorld>());
        Setpieces = new List<string>(setpieces = new List<string>());
        BiomeData = new ReadOnlyDictionary<string, BiomeData>(biomes = new Dictionary<string, BiomeData>());

        var basePath = Path.GetFullPath(dir);
        LoadWorldsAndSetpieces(gameData, basePath, setpieces, worlds);
        // World-by-world basis spawn data & taunt data
        LoadOverseerAndSetpieceData(basePath, biomes);
    }

    private void LoadOverseerAndSetpieceData(string basePath, Dictionary<string, BiomeData> biomes)
    {
        var xmls = Directory.EnumerateFiles(basePath, "*.xml", SearchOption.AllDirectories).ToArray();
        for (var i = 0; i < xmls.Length; i++)
        {
            // I wonder a backslash check works on all OSes, I'll put this just in case...
            var arr = xmls[i].Replace("\\", "/").Split('/');
            var fileName = arr[arr.Length - 1];
            int j;
            var folderName = new StringBuilder();
            var baseIndex = 0;
            // find base worlds folder
            for (j = 0; j < arr.Length; j++)
                if (arr[j] == "worlds")
                {
                    baseIndex = j + 1;
                    break;
                }

            for (j = baseIndex; j < arr.Length - 1; j++)
            {
                folderName.Append(arr[j]);
                // folder separation
                if (arr.Length - j - 1 > 1)
                    folderName.Append(".");
            }

            var node = XElement.Parse(File.ReadAllText(xmls[i]));
            if (fileName.ToLowerInvariant() == "data.xml")
                biomes[folderName.ToString()] = new BiomeData(node, Data);
        }
    }

    private void LoadWorldsAndSetpieces(XmlData gameData, string basePath, List<string> setpieces,
        Dictionary<string, ProtoWorld> worlds)
    {
        var jwFiles = Directory.EnumerateFiles(basePath, "*.jw", SearchOption.AllDirectories).ToArray();
        for (var i = 0; i < jwFiles.Length; i++)
        {
            Log.Info("Initializing world data: " + Path.GetFileName(jwFiles[i]) + " {0}/{1}...", i + 1,
                jwFiles.Length);

            var jw = File.ReadAllText(jwFiles[i]);
            var world = JsonConvert.DeserializeObject<ProtoWorld>(jw);

            if (world.setpiece)
                setpieces.Add(world.name);

            var di = Directory.GetParent(jwFiles[i]);
            var mapFile = Path.Combine(di.FullName, world.map);
            if (world.map.EndsWith(".em"))
                world.mapData = File.ReadAllBytes(mapFile);

            worlds.Add(world.name, world);
        }
    }

    public ProtoWorld this[string name] => Data[name];
}