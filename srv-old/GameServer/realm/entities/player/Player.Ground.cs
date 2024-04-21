using Shared;
using Shared.resources;
using GameServer.realm.worlds;

namespace GameServer.realm.entities.player; 

public partial class Player
{
    public void ForceGroundHit(float x, float y, long time) {
        if (HasConditionEffect(ConditionEffects.Invulnerable))
            return;

        var tile = Owner.Map[(int) x, (int) y];
        var objDesc = tile.ObjType == 0 ? null : Manager.Resources.GameData.ObjectDescs[tile.ObjType];
        var tileDesc = Manager.Resources.GameData.Tiles[tile.TileType];
        
        var dmg = tileDesc.Damage;
        if (dmg <= 0 || (objDesc != null && objDesc.ProtectFromGroundDamage))
            return;
        
        HP -= dmg;
        
        foreach (var plr in Owner.Players.Values)
            if (plr != this && MathUtils.DistSqr(X, Y, plr.X, plr.Y) < 16 * 16)
                plr.Client.SendDamage(Id, 0, (ushort)dmg, HP < 0, 0, 0);

        if (HP <= 0)
            Death(tileDesc.ObjectId, tile: tile);
    }
}