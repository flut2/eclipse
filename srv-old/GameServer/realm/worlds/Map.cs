using Shared.resources;
using Shared.terrain;
using DungeonGenerator.Dungeon;
using Ionic.Zlib;
using NLog;

namespace GameServer.realm.worlds; 

public class MapTile {
    public byte UpdateCount = 1;

    private ushort cTileType;
    private TileDesc cTileDesc;
    private int cObjId;
    private ushort cObjType;
    private ObjectDesc cObjDesc;
    private TileRegion cRegion;

    public ushort TileType;
    public TileDesc TileDesc;
    public int ObjId;
    public ushort ObjType;
    public ObjectDesc ObjDesc;
    public TileRegion Region;

    public long SightRegion = 1;
    
    public void Cache() {
        cTileType = TileType;
        cTileDesc = TileDesc;
        cObjId = ObjId;
        cObjType = ObjType;
        cObjDesc = ObjDesc;
        cRegion = Region;
    }

    public void Reset() {
        TileType = cTileType;
        TileDesc = cTileDesc;
        ObjId = cObjId;
        ObjType = cObjType;
        ObjDesc = cObjDesc;
        Region = cRegion;
        UpdateCount++;
    }

    public MapTile Clone() {
        return new MapTile {
            UpdateCount = (byte) (UpdateCount + 1),
            TileType = TileType,
            TileDesc = TileDesc,
            ObjId = ObjId,
            ObjType = ObjType,
            ObjDesc = ObjDesc,
            Region = Region,
            SightRegion = SightRegion
        };
    }

    public void CopyTo(MapTile tile) {
        tile.TileType = TileType;
        tile.TileDesc = TileDesc;
        tile.ObjType = ObjType;
        tile.ObjDesc = ObjDesc;
        tile.Region = Region;
    }

    public ObjectDef ToDef(int x, int y) {
        return new ObjectDef {
            ObjectType = ObjType,
            Stats = new ObjectStats {
                Id = ObjId,
                X = x + 0.5f,
                Y = y + 0.5f,
                StatTypes = Array.Empty<KeyValuePair<StatsType, object>>()
            }
        };
    }
}

public struct TileStruct {
    public ushort TileType;
    public ushort ObjType;
    public TileRegion Region;
}

public class Map {
    private Logger Log = LogManager.GetCurrentClassLogger();
    private XmlData _dat;

    public int Width;
    public int Height;

    public readonly Dictionary<IntPoint, TileRegion> Regions;
    private Tuple<IntPoint, ushort>[] _entities;

    private MapTile[,] _tiles;

    public MapTile this[int x, int y] {
        get => _tiles[x, y];
        set => _tiles[x, y] = value;
    }

    public Map(XmlData dat) {
        _dat = dat;
        Regions = new Dictionary<IntPoint, TileRegion>();
    }

    public bool Contains(IntPoint point) {
        var x = point.X;
        var y = point.Y;

        return x >= 0 && x < Width &&
               y >= 0 && y < Height;
    }

    public bool Contains(int x, int y) {
        return x >= 0 && x < Width &&
               y >= 0 && y < Height;
    }

    public int Load(Stream stream, int idBase) {
        using var rdr = new BinaryReader(new ZlibStream(stream, CompressionMode.Decompress));

        var ver = rdr.ReadByte();
        int enCount;
        List<Tuple<IntPoint, ushort>> entities;
        switch (ver) {
            case 1:
                /*startX*/ rdr.ReadUInt16();
                /*startY*/ rdr.ReadUInt16();
                Width = rdr.ReadUInt16();
                Height = rdr.ReadUInt16();
                _tiles = new MapTile[Width, Height];
                enCount = 0;
                entities = new List<Tuple<IntPoint, ushort>>();
                for (var y = 0; y < Height; y++)
                for (var x = 0; x < Width; x++) {
                    var groundType = rdr.ReadUInt16();
                    if (groundType == ushort.MaxValue)
                        groundType = 255;
            
                    var objType = rdr.ReadUInt16();
                    var regionType = (TileRegion) rdr.ReadByte();

                    ObjectDesc objDesc = null;
                    if (objType != ushort.MaxValue) {
                        objDesc = _dat.ObjectDescs[objType];
                        if (objDesc == null || !objDesc.Static || objDesc.Enemy) {
                            entities.Add(new Tuple<IntPoint, ushort>(new IntPoint(x, y), objType));
                            if (objDesc == null || !(objDesc.Enemy && objDesc.Static))
                                objType = ushort.MaxValue;
                        }
                    }

                    var objId = 0;
                    if (objType != ushort.MaxValue && (objDesc == null || !(objDesc.Enemy && objDesc.Static))) {
                        enCount++;
                        objId = idBase + enCount;
                    }

                    if (objType == ushort.MaxValue)
                        objType = 0;

                    if (regionType != TileRegion.EM_Empty)
                        Regions.Add(new IntPoint(x, y), regionType);
                    else regionType = TileRegion.None;

                    var tile = new MapTile {
                        TileType = groundType,
                        TileDesc = _dat.Tiles[groundType],
                        ObjType = objType,
                        ObjDesc = objDesc,
                        ObjId = objId,
                        Region = regionType
                    };
                    tile.Cache();
                    _tiles[x, y] = tile;
                }

                _entities = entities.ToArray();
                return enCount;
            case 2:
                /*startX*/ rdr.ReadUInt16();
                /*startY*/ rdr.ReadUInt16();
                Width = rdr.ReadUInt16();
                Height = rdr.ReadUInt16();
                _tiles = new MapTile[Width, Height];
                var structs = new TileStruct[rdr.ReadUInt16()];
                for (var i = 0; i < structs.Length; i++)
                    structs[i] = new TileStruct {
                        TileType = rdr.ReadUInt16(),
                        ObjType = rdr.ReadUInt16(),
                        Region = (TileRegion) rdr.ReadByte()
                    };
                var byteRead = structs.Length <= 256;
                enCount = 0;
                entities = new List<Tuple<IntPoint, ushort>>();
                for (var y = 0; y < Height; y++)
                for (var x = 0; x < Width; x++) {
                    var tileStruct = structs[byteRead ? rdr.ReadByte() : rdr.ReadUInt16()];
                    var groundType = tileStruct.TileType;
                    if (groundType == ushort.MaxValue)
                        groundType = 255;
            
                    var objType = tileStruct.ObjType;
                    var regionType = tileStruct.Region;

                    ObjectDesc objDesc = null;
                    if (objType != ushort.MaxValue) {
                        objDesc = _dat.ObjectDescs[objType];
                        if (objDesc == null || !objDesc.Static || objDesc.Enemy) {
                            entities.Add(new Tuple<IntPoint, ushort>(new IntPoint(x, y), objType));
                            if (objDesc == null || !(objDesc.Enemy && objDesc.Static))
                                objType = ushort.MaxValue;
                        }
                    }

                    var objId = 0;
                    if (objType != ushort.MaxValue && (objDesc == null || !(objDesc.Enemy && objDesc.Static))) {
                        enCount++;
                        objId = idBase + enCount;
                    }

                    if (objType == ushort.MaxValue)
                        objType = 0;

                    if (regionType != TileRegion.EM_Empty)
                        Regions.Add(new IntPoint(x, y), regionType);
                    else regionType = TileRegion.None;

                    var tile = new MapTile {
                        TileType = groundType,
                        TileDesc = _dat.Tiles[groundType],
                        ObjType = objType,
                        ObjDesc = objDesc,
                        ObjId = objId,
                        Region = regionType
                    };
                    tile.Cache();
                    _tiles[x, y] = tile;
                }

                _entities = entities.ToArray();
                return enCount;
            default:
                throw new NotSupportedException($"Unsupported Eclipse Map (*.em) version {ver}");
        }
    }

    public int Load(DungeonTile[,] tiles, int idBase) {
        return 0;
        /*Width = tiles.GetLength(0);
        Height = tiles.GetLength(1);

        var wTiles = new WmapDesc[Width, Height];
        for (var i = 0; i < Width; i++)
        for (var j = 0; j < Height; j++) {
            var dTile = tiles[i, j];

            var wTile = new WmapDesc();
            wTile.TileId = _dat.IdToTileType[dTile.TileType.Name];
            wTile.TileDesc = _dat.Tiles[wTile.TileId];
            wTile.Region = (dTile.Region == null)
                ? TileRegion.None
                : (TileRegion)Enum.Parse(typeof(TileRegion), dTile.Region);
            if (dTile.Object != null) {
                wTile.ObjType = _dat.IdToObjectType[dTile.Object.ObjectType.Name];
                _dat.ObjectDescs.TryGetValue(wTile.ObjType, out wTile.ObjDesc);
            }

            wTiles[i, j] = wTile;
        }

        _tiles = new WmapTile[Width, Height];

        var enCount = 0;
        var entities = new List<Tuple<IntPoint, ushort>>();
        for (var y = 0; y < Height; y++)
        for (var x = 0; x < Width; x++) {
            var tile = new WmapTile(wTiles[x, y]);

            if (tile.Region != 0)
                Regions.Add(new IntPoint(x, y), tile.Region);

            var desc = tile.ObjDesc;
            if (tile.ObjType != 0 && (desc == null || !desc.Static || desc.Enemy)) {
                entities.Add(new Tuple<IntPoint, ushort>(new IntPoint(x, y), tile.ObjType));
                if (desc == null || !(desc.Enemy && desc.Static))
                    tile.ObjType = 0;
            }

            if (tile.ObjType != 0 && (desc == null || !(desc.Enemy && desc.Static))) {
                enCount++;
                tile.ObjId = idBase + enCount;
            }

            _tiles[x, y] = tile;
        }

        _entities = entities.ToArray();
        return enCount;*/
    }

    public IEnumerable<Entity> InstantiateEntities(RealmManager manager, IntPoint offset = new()) {
        foreach (var i in _entities) {
            var entity = Entity.Resolve(manager, i.Item2);
            entity.Move(i.Item1.X + 0.5f + offset.X, i.Item1.Y + 0.5f + offset.Y);
            yield return entity;
        }
    }

    public void ResetTiles() {
        Regions.Clear();
        for (var y = 0; y < Height; y++)
        for (var x = 0; x < Width; x++) {
            var t = _tiles[x, y];
            t.Reset();
            if (t.Region != 0)
                Regions.Add(new IntPoint(x, y), t.Region);
        }
    }

    // typically this method is used with setpieces. It's data is
    // copied to the supplied world at the said position
    public void ProjectOntoWorld(World world, IntPoint pos) {
        for (var y = 0; y < Height; y++)
        for (var x = 0; x < Width; x++) {
            var projX = pos.X + x;
            var projY = pos.Y + y;
            if (!world.Map.Contains(projX, projY))
                continue;

            var tile = world.Map[projX, projY];

            var spTile = _tiles[x, y];
            if (spTile.TileType == 255)
                continue;
            spTile.CopyTo(tile);

            if (spTile.ObjId != 0)
                tile.ObjId = world.GetNextEntityId();

            if (tile.Region != 0)
                world.Map.Regions.Add(new IntPoint(projX, projY), spTile.Region);

            tile.UpdateCount++;
        }

        foreach (var e in InstantiateEntities(world.Manager, pos)) {
            if (!world.Map.Contains((int) e.X, (int) e.Y))
                continue;

            world.EnterWorld(e);
        }
    }
}