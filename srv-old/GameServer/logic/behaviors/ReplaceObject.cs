using System.Xml.Linq;
using Shared;
using Shared.resources;
using GameServer.realm;
using GameServer.realm.entities.player;

namespace GameServer.logic.behaviors; 

internal class ReplaceObject : Behavior
{
    private readonly string _objName;
    private readonly string _replacedObjName;
    private readonly int _range;

    public ReplaceObject(XElement e)
    {
        _objName = e.ParseString("@objName");
        _replacedObjName = e.ParseString("@replacedName");
        _range = e.ParseInt("@range");
    }

    public ReplaceObject(string objName, string replacedObjName, int range)
    {
        _objName = objName;
        _replacedObjName = replacedObjName;
        _range = range;
    }

    protected override void OnStateEntry(Entity host, RealmTime time, ref object state)
    {
        var dat = host.Manager.Resources.GameData;
        var objId = dat.IdToObjectType[_objName];
        var replacedObjId = dat.IdToObjectType[_replacedObjName];

        var map = host.Owner.Map;

        var w = map.Width;
        var h = map.Height;

        for (var y = 0; y < h; y++)
        for (var x = 0; x < w; x++)
        {
            var tile = map[x, y];

            if (tile.ObjType != objId || tile.ObjType == replacedObjId)
                continue;

            var dx = Math.Abs(x - (int)host.X);
            var dy = Math.Abs(y - (int)host.Y);

            if (dx > _range || dy > _range)
                continue;

            if (tile.ObjDesc?.BlocksSight == true)
            {
                if (host.Owner.Blocking == 3)
                    Sight.UpdateRegion(map, x, y);

                foreach (var plr in host.Owner.Players.Values
                             .Where(p => MathsUtils.DistSqr(p.X, p.Y, x, y) < Player.VISIBILITY_RADIUS_SQR))
                    plr.Sight.UpdateCount++;
            }

            tile.ObjType = replacedObjId;
            if (tile.ObjId == 0)
                tile.ObjId = host.Owner.GetNextEntityId();
            tile.UpdateCount++;
            map[x, y] = tile;
        }
    }

    protected override void TickCore(Entity host, RealmTime time, ref object state)
    {
    }
}