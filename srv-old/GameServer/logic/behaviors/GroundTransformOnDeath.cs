using System.Xml.Linq;
using Shared;
using GameServer.realm;

namespace GameServer.logic.behaviors; 

public class GroundTransformOnDeath : Behavior
{
    private readonly string _tileId;
    private readonly int _radius;
    private readonly int? _relativeX;
    private readonly int? _relativeY;

    public GroundTransformOnDeath(XElement e)
    {
        _tileId = e.ParseString("@tileId");
        _radius = e.ParseInt("@radius");
        _relativeX = e.ParseNInt("@relativeX");
        _relativeY = e.ParseNInt("@relativeY");
    }
        
    public GroundTransformOnDeath(
        string tileId,
        int radius = 0,
        int? relativeX = null,
        int? relativeY = null)
    {
        _tileId = tileId;
        _radius = radius;
        _relativeX = relativeX;
        _relativeY = relativeY;
    }

    protected internal override void Resolve(State parent)
    {
        parent.Death += (sender, e) =>
        {
            var host = e.Host;
            var map = host.Owner.Map;
            var hx = (int)host.X;
            var hy = (int)host.Y;

            var tileType = host.Manager.Resources.GameData.IdToTileType[_tileId];

            if (_relativeX != null && _relativeY != null)
            {
                var x = hx + (int)_relativeX;
                var y = hy + (int)_relativeY;

                if (!map.Contains(new IntPoint(x, y)))
                    return;

                var tile = map[x, y];

                if (tileType == tile.TileType)
                    return;

                tile.TileType = tileType;
                tile.UpdateCount++;
                return;
            }

            for (var i = hx - _radius; i <= hx + _radius; i++)
            for (var j = hy - _radius; j <= hy + _radius; j++)
            {
                if (!map.Contains(new IntPoint(i, j)))
                    continue;

                var tile = map[i, j];

                if (tileType == tile.TileType)
                    continue;

                tile.TileType = tileType;
                tile.UpdateCount++;
            }
        };
    }

    protected override void TickCore(Entity host, RealmTime time, ref object state)
    {
    }
}