using Shared.resources;

namespace GameServer.realm.entities.player; 

public partial class Player
{
    internal Projectile PlayerShootProjectile(
        byte id, ProjectileDesc desc, ushort objType, float x, float y)
    {
        bulletId = id;
        return CreateProjectile(desc, objType, x, y);
    }
}