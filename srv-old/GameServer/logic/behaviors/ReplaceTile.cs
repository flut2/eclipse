using System.Xml.Linq;
using Shared;
using Shared.resources;
using GameServer.realm;
using GameServer.realm.entities.player;

namespace GameServer.logic.behaviors; 

internal class ReplaceTile : Behavior
{
    private readonly string _objName;
    private readonly string _replacedObjName;
    private readonly int _range;

    public ReplaceTile(XElement e)
    {
        _objName = e.ParseString("@objName");
        _replacedObjName = e.ParseString("@replacedObjName");
        _range = e.ParseInt("@range");
    }
        
    public ReplaceTile(string objName, string replacedObjName, int range)
    {
        _objName = objName;
        _range = range;
        _replacedObjName = replacedObjName;
    }

    protected override void OnStateEntry(Entity host, RealmTime time, ref object state)
    {
        //var objType = GetObjType(_objName);
        var dat = host.Manager.Resources.GameData;
        var tileId = dat.IdToTileType[_objName];
        var replacedTileId = dat.IdToTileType[_replacedObjName];

        var map = host.Owner.Map;

        var w = map.Width;
        var h = map.Height;

        for (var y = 0; y < h; y++)
        for (var x = 0; x < w; x++)
        {
            var tile = map[x, y];

            if (tile.TileType != tileId || tile.TileType == replacedTileId)
                continue;

            var dx = Math.Abs(x - (int)host.X);
            var dy = Math.Abs(y - (int)host.Y);

            if (dx > _range || dy > _range)
                continue;

            if (tile.ObjDesc?.BlocksSight == true)
            {
                foreach (var plr in host.Owner.Players.Values.Where(p => MathsUtils.DistSqr(p.X, p.Y, x, y) < Player.VISIBILITY_RADIUS_SQR))
                    plr.Sight.UpdateCount++;
            }

            tile.TileType = replacedTileId;
            if (tile.ObjId == 0)
                tile.ObjId = host.Owner.GetNextEntityId();
            tile.UpdateCount++;
            map[x, y] = tile;
        }
    }

    protected override void TickCore(Entity host, RealmTime time, ref object state) { }
}