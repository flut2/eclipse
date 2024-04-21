using Shared;
using Shared.resources;
using GameServer.realm.entities;
using GameServer.realm.entities.player;
using GameServer.realm.worlds;
using wServer.realm;

namespace GameServer.realm; 

internal static class EntityUtils {
    public static double DistSqr(this Entity a, Entity b) {
        var dx = a.X - b.X;
        var dy = a.Y - b.Y;
        return dx * dx + dy * dy;
    }

    public static double Dist(this Entity a, Entity b) {
        return Math.Sqrt(a.DistSqr(b));
    }

    public static bool AnyPlayerNearby(this Entity entity, int radius = Player.VISIBILITY_RADIUS) {
        foreach (var i in entity.Owner.PlayersCollision.HitTest(entity.X, entity.Y, radius)
                     .Where(e => e is Player)) {
            if (i.HasConditionEffect(ConditionEffects.Hidden))
                continue;

            var d = i.DistSqr(entity);
            if (d < radius * radius)
                return true;
        }

        return false;
    }

    public static bool AnyPlayerNearby(this World world, double x, double y, int radius = Player.VISIBILITY_RADIUS) {
        foreach (var i in world.PlayersCollision.HitTest(x, y, radius).Where(e => e is Player)) {
            if (i.HasConditionEffect(ConditionEffects.Hidden))
                continue;

            var d = MathsUtils.DistSqr(i.X, i.Y, x, y);
            if (d < radius * radius)
                return true;
        }

        return false;
    }

    public static bool AnyEnemyNearby(this Entity entity, int radius = Player.VISIBILITY_RADIUS) {
        foreach (var i in entity.Owner.EnemiesCollision.HitTest(entity.X, entity.Y, radius)) {
            if (!(i is Enemy) || entity == i)
                continue;

            var d = i.DistSqr(entity);
            if (d < radius * radius)
                return true;
        }

        return false;
    }

    /*public static bool AnyEnemyNearby(this World world, double x, double y, int radius = Player.Radius)
    {
        foreach (var i in world.EnemiesCollision.HitTest(x, y, radius))
        {
            if (!(i is Enemy))
                continue;

            var d = MathsUtils.DistSqr(i.X, i.Y, x, y);
            if (d < radius * radius)
                return true;
        }
        return false;
    }*/

    public static Entity
        GetLowestHpEntity(this Entity entity, double dist, ushort? objType,
            bool seeInvis = false) // objType = null for player
    {
        var entities = entity.GetNearestEntities(dist, objType, seeInvis).OfType<Character>();
        if (!entities.Any())
            return null;

        var lowestHp = entities.Min(e => e.HP);
        return entities.FirstOrDefault(e => e.HP == lowestHp);
    }

    /*public static IEnumerable<Entity> GetNearestEntities(this Entity entity, double dist) // for ENEMIES
    {
        if (entity.Owner == null)
            yield break;
        foreach (Entity i in entity.Owner.EnemiesCollision.HitTest(entity.X, entity.Y, (float)dist))
        {
            double d = i.Dist(entity);
            if (d < dist)
                yield return i;
        }
    }*/

    public static Entity
        GetNearestEntity(this Entity entity, double dist, ushort? objType, bool seeInvis = false) //Null for player
    {
        //return entity.GetNearestEntities(dist, objType).FirstOrDefault();

        // function speed might be a problem
        var entities = entity.GetNearestEntities(dist, objType, seeInvis).ToArray();
        if (entities.Length <= 0)
            return null;
        return entities.Aggregate(
            (curmin, x) => (curmin == null || x.DistSqr(entity) < curmin.DistSqr(entity) ? x : curmin));
    }

    public static IEnumerable<Entity> GetNearestEntities(this Entity entity, double dist, ushort? objType,
        bool seeInvis = false) //Null for player
    {
        if (entity.Owner == null) yield break;
        if (objType == null)
            foreach (var i in entity.Owner.PlayersCollision.HitTest(entity.X, entity.Y, dist)
                         .Where(e => e is IPlayer)) {
                if (!seeInvis && !(i as IPlayer).IsVisibleToEnemy()) continue;
                var d = i.Dist(entity);
                if (d < dist)
                    yield return i;
            }
        else
            foreach (var i in entity.Owner.EnemiesCollision.HitTest(entity.X, entity.Y, dist)) {
                if (i.ObjectType != objType.Value) continue;
                var d = i.Dist(entity);
                if (d < dist)
                    yield return i;
            }
    }

    /*public static IEnumerable<Entity> GetNearestEntitiesBySquare(this Entity entity, double dist, ushort? objType, bool seeInvis = false)   //Null for player
    {
        if (entity.Owner == null) yield break;
        if (objType == null)
            foreach (var i in entity.Owner.PlayersCollision.HitTest(entity.X, entity.Y, dist).Where(e => e is IPlayer))
            {
                if (!seeInvis && !(i as IPlayer).IsVisibleToEnemy()) continue;
                var d = i.Dist(entity);
                if (d < dist)
                    yield return i;
            }
        else
            foreach (var i in entity.Owner.EnemiesCollision.HitTest(entity.X, entity.Y, dist))
            {
                if (i.ObjectType != objType.Value) continue;
                var d = i.Dist(entity);
                if (d < dist)
                    yield return i;
            }
    }*/

    public static Entity GetNearestEntity(this Entity entity, double dist, bool players,
        Predicate<Entity> predicate = null) {
        if (entity.Owner == null) return null;
        Entity ret = null;
        if (players)
            foreach (var i in entity.Owner.PlayersCollision.HitTest(entity.X, entity.Y, dist)
                         .Where(e => e is IPlayer)) {
                if (!(i as IPlayer).IsVisibleToEnemy() ||
                    i == entity) continue;
                var d = i.Dist(entity);
                if (d < dist) {
                    if (predicate != null && !predicate(i))
                        continue;
                    dist = d;
                    ret = i;
                }
            }
        else
            foreach (var i in entity.Owner.EnemiesCollision.HitTest(entity.X, entity.Y, dist)) {
                if (i == entity) continue;
                var d = i.Dist(entity);
                if (d < dist) {
                    if (predicate != null && !predicate(i))
                        continue;
                    dist = d;
                    ret = i;
                }
            }

        return ret;
    }

    public static Entity GetNearestEntityByGroup(this Entity entity, double dist, string group) {
        //return entity.GetNearestEntitiesByGroup(dist, group).FirstOrDefault();

        // function speed might be a problem
        var entities = entity.GetNearestEntitiesByGroup(dist, group).ToArray();
        if (entities.Length <= 0)
            return null;
        return entities.Aggregate(
            (curmin, x) => (curmin == null || x.DistSqr(entity) < curmin.DistSqr(entity) ? x : curmin));
    }

    public static IEnumerable<Entity> GetNearestEntitiesByGroup(this Entity entity, double dist, string group) {
        if (entity.Owner == null)
            yield break;
        foreach (var i in entity.Owner.EnemiesCollision.HitTest(entity.X, entity.Y, dist)) {
            if (i.ObjectDesc == null ||
                i.ObjectDesc.Group == null ||
                !i.ObjectDesc.Group.Equals(
                    group, StringComparison.InvariantCultureIgnoreCase))
                continue;
            var d = i.Dist(entity);
            if (d < dist)
                yield return i;
        }
    }

    public static Entity GetNearestEntityByName(this Entity entity, double dist, string id) {
        //return entity.GetNearestEntitiesByName(dist, id).FirstOrDefault();

        // function speed might be a problem
        var entities = entity.GetNearestEntitiesByName(dist, id).ToArray();
        if (entities.Length <= 0)
            return null;
        return entities.Aggregate(
            (curmin, x) => (curmin == null || x.DistSqr(entity) < curmin.DistSqr(entity) ? x : curmin));
    }

    public static IEnumerable<Entity> GetNearestEntitiesByName(this Entity entity, double dist, string id) {
        if (entity.Owner == null)
            yield break;
        foreach (var i in entity.Owner.EnemiesCollision.HitTest(entity.X, entity.Y, dist)) {
            if (i.ObjectDesc == null || (id != null && !i.ObjectDesc.ObjectId.ContainsIgnoreCase(id)))
                continue;

            var d = i.Dist(entity);
            if (d < dist)
                yield return i;
        }
    }

    public static int CountEntity(this Entity entity, double dist, ushort? objType) {
        if (entity.Owner == null) return 0;
        var ret = 0;
        if (objType == null)
            foreach (var i in entity.Owner.PlayersCollision.HitTest(entity.X, entity.Y, dist)
                         .Where(e => e is Player)) {
                if (!(i as IPlayer).IsVisibleToEnemy()) continue;
                var d = i.Dist(entity);
                if (d < dist)
                    ret++;
            }
        else
            foreach (var i in entity.Owner.EnemiesCollision.HitTest(entity.X, entity.Y, dist)) {
                if (i.ObjectType != objType.Value) continue;
                var d = i.Dist(entity);
                if (d < dist)
                    ret++;
            }

        return ret;
    }

    public static int CountEntity(this Entity entity, double dist, string group) {
        if (entity.Owner == null) return 0;
        var ret = 0;
        foreach (var i in entity.Owner.EnemiesCollision.HitTest(entity.X, entity.Y, dist)) {
            if (i.ObjectDesc == null || i.ObjectDesc.Group != group) continue;
            var d = i.Dist(entity);
            if (d < dist)
                ret++;
        }

        return ret;
    }

    public static float GetSpeed(this Entity entity, float speed)
    {
        var ret = speed;
        if(entity.HasConditionEffect(ConditionEffects.Slowed))
            ret *= 0.5f;
        return ret * 5.0f; // we move at 5 tps speeds even at a different tps
    }

    // public static float GetSpeed(this Entity entity, float spdMult) {
        // return (entity.HasConditionEffect(ConditionEffects.Slowed) ? 4 : 4 + 5.6f) * spdMult;
    // }

    public static void
        AOE(this Entity entity, float radius, ushort? objType, Action<Entity> callback) //Null for player
    {
        if (objType == null)
            foreach (var i in entity.Owner.PlayersCollision.HitTest(entity.X, entity.Y, radius)
                         .Where(e => e is Player)) {
                var d = i.Dist(entity);
                if (d < radius)
                    callback(i);
            }
        else
            foreach (var i in entity.Owner.EnemiesCollision.HitTest(entity.X, entity.Y, radius)) {
                if (i.ObjectType != objType.Value) continue;
                var d = i.Dist(entity);
                if (d < radius)
                    callback(i);
            }
    }

    public static void
        AOE(this Entity entity, float radius, bool players, Action<Entity> callback) //Null for player
    {
        if (players)
            foreach (var i in entity.Owner.PlayersCollision.HitTest(entity.X, entity.Y, radius)
                         .Where(e => e is Player)) {
                var d = i.Dist(entity);
                if (d < radius)
                    callback(i);
            }
        else
            foreach (var i in entity.Owner.EnemiesCollision.HitTest(entity.X, entity.Y, radius)) {
                if (!(i is Enemy)) continue;
                var d = i.Dist(entity);
                if (d < radius)
                    callback(i);
            }
    }

    public static void
        AOE(this World world, Position pos, float radius, bool players, Action<Entity> callback) //Null for player
    {
        if (players)
            foreach (var i in world.PlayersCollision.HitTest(pos.X, pos.Y, radius).Where(e => e is Player)) {
                var d = MathsUtils.Dist(i.X, i.Y, pos.X, pos.Y);
                if (d < radius)
                    callback(i);
            }
        else
            foreach (var i in world.EnemiesCollision.HitTest(pos.X, pos.Y, radius)) {
                var e = i as Enemy;
                if (e == null || e.ObjectDesc.Static)
                    continue;

                var d = MathsUtils.Dist(i.X, i.Y, pos.X, pos.Y);
                if (d < radius)
                    callback(i);
            }
    }

    public static void ForceUpdate(this Entity e, int slot) {
        if (e == null || e is not Player)
            return;

        switch (slot) {
            /*case 254:
                e.InvokeStatChange(
                    StatsType.HealthStackCount, (e as Player).HealthPots.Count);
                break;
            case 255:
                e.InvokeStatChange(
                    StatsType.MagicStackCount, (e as Player).MagicPots.Count);
                break;*/
            default:
                //e.InvokeStatChange(StatsType.Inventory, (e as IContainer).Inventory.GetItems());
                break;
        }
    }

    public static Entity GetNearestTauntedPlayer(this Entity entity, double dist) {
        // function speed might be a problem
        var entities = entity.GetNearestTauntedPlayers(dist).ToArray();
        if (entities.Length <= 0)
            return null;
        return entities.Aggregate(
            (curmin, x) => (curmin == null || x.DistSqr(entity) < curmin.DistSqr(entity) ? x : curmin));
    }

    public static bool TauntedPlayerNearby(this Entity entity, double radius) {
        foreach (var i in entity.Owner.PlayersCollision.HitTest(entity.X, entity.Y, radius)) {
            if (!(i is Player) || !i.HasConditionEffect(ConditionEffects.Targeted) || entity == i)
                continue;

            var d = i.DistSqr(entity);
            if (d < radius * radius)
                return true;
        }

        return false;
    }

    public static IEnumerable<Entity> GetNearestTauntedPlayers(this Entity entity, double dist) {
        if (entity.Owner == null) yield break;
        foreach (var i in entity.Owner.PlayersCollision.HitTest(entity.X, entity.Y, dist)
                     .Where(e => e is IPlayer)) {
            if (!(i is Player p) || !p.HasConditionEffect(ConditionEffects.Targeted) ||
                p.Client.Account.Hidden && p.HasConditionEffect(ConditionEffects.Hidden)) continue;
            var d = i.Dist(entity);
            if (d < dist)
                yield return i;
        }
    }
}

internal static class ItemUtils {
    public static int NO_ITEM = -1;
    public static int ALL_TYPE = 0;
    public static int BOOTS_TYPE = 9;
    public static int ARTIFACT_TYPE = 23;
    public static int CONSUMABLE_TYPE = 10;
    public static int SWORD_TYPE = 1;
    public static int BOW_TYPE = 3;
    public static int STAFF_TYPE = 17;
    public static int ANY_WEAPON_TYPE = 22;
    public static int[] WEAPON_TYPES = {SWORD_TYPE, BOW_TYPE, STAFF_TYPE};

    public static int LEATHER_TYPE = 6;
    public static int HEAVY_TYPE = 7;
    public static int ROBE_TYPE = 14;
    public static int ANY_ARMOR_TYPE = 20;
    public static int[] ARMOR_TYPES = {LEATHER_TYPE, HEAVY_TYPE, ROBE_TYPE};

    public static bool AuditItem(this IContainer container, Item item, int slot) {
        return item == null || container.SlotTypes[slot] == 0 || SlotsMatching(item.SlotType, container.SlotTypes[slot]);
    }

    public static bool SlotsMatching(int slot1, int slot2) {
        if (slot1 == ALL_TYPE || slot2 == ALL_TYPE)
            return true;

        if ((WEAPON_TYPES.Contains(slot1) && slot2 == ANY_WEAPON_TYPE) ||
            (WEAPON_TYPES.Contains(slot2) && slot1 == ANY_WEAPON_TYPE) ||
            (ARMOR_TYPES.Contains(slot1) && slot2 == ANY_ARMOR_TYPE) ||
            (ARMOR_TYPES.Contains(slot2) && slot1 == ANY_ARMOR_TYPE)) {
            return true;
        }

        return slot1 == slot2;
    }
}