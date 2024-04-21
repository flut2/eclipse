using System.Xml.Linq;
using Shared;
using GameServer.realm;
using GameServer.realm.entities.player;

namespace GameServer.logic.behaviors; 

internal class RemoveTileObject : Behavior
{
    private readonly ushort _objType;
    private readonly int _range;

    public RemoveTileObject(XElement e)
    {
        _objType = GetObjType(e.ParseString("@type"));
        _range = e.ParseInt("@range");
    }
        
    public RemoveTileObject(string objType, int range)
    {
        _objType = GetObjType(objType);
        _range = range;
    }

    protected override void OnStateEntry(Entity host, RealmTime time, ref object state)
    {
        var objType = _objType;
        var map = host.Owner.Map;
        for (var y = (int)host.Y - _range; y <= (int)host.Y + _range; y++)
        for (var x = (int)host.X - _range; x <= (int)host.X + _range; x++)
        {
            var tile = map[x, y];
            if (tile.ObjType != objType)
                continue;
                
            if (tile.ObjDesc?.BlocksSight == true)
            {
                if (host.Owner.Blocking == 3)
                    Sight.UpdateRegion(map, x, y);
                    
                foreach (var plr in host.Owner.Players.Values
                             .Where(p => MathsUtils.DistSqr(p.X, p.Y, x, y) < Player.VISIBILITY_RADIUS_SQR))
                    plr.Sight.UpdateCount++;
            }

            tile.ObjType = 0;
            if (tile.ObjId == 0)
                tile.ObjId = host.Owner.GetNextEntityId();
            tile.UpdateCount++;
            map[x, y] = tile;
        }
    }

    protected override void TickCore(Entity host, RealmTime time, ref object state) { }
}