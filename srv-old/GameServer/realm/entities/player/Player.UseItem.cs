using Dynamitey.Internal.Optimization;
using Shared;
using Shared.resources;
using GameServer.realm.worlds;
using GameServer.realm.worlds.logic;
using wServer.realm;

namespace GameServer.realm.entities.player; 

partial class Player {
    public const int MaxAbilityDist = 14;

    public static readonly ConditionEffect[] NegativeEffs = {
        new() {
            Effect = ConditionEffectIndex.Slowed,
            DurationMS = 0
        },
        new() {
            Effect = ConditionEffectIndex.Weak,
            DurationMS = 0
        },
        new() {
            Effect = ConditionEffectIndex.Bleeding,
            DurationMS = 0
        },
        new() {
            Effect = ConditionEffectIndex.Sick,
            DurationMS = 0
        }
    };

    private readonly object _useLock = new();

    public void UseItem(int objId, int slot, float x, float y) {
        lock (_useLock) {
            var entity = Owner.GetEntity(objId);
            if (entity == null) {
                Client.SendInvResult(1);
                return;
            }

            if (entity is Player && objId != Id) {
                Client.SendInvResult(1);
                return;
            }

            var container = entity as IContainer;

            // eheh no more clearing BBQ loot bags
            if (this.Dist(entity) > 3) {
                Client.SendInvResult(1);
                return;
            }

            var cInv = container?.Inventory.CreateTransaction();

            // get item
            Item item = null;
            if (item == null) {
                if (container == null)
                    return;

                item = cInv[slot];
            }

            if (item == null)
                return;

            // make sure not trading and trying to consume item
            if (tradeTarget != null && item.Consumable)
                return;

            // use item
            var slotType = 10;
            if (slot < cInv.Length) {
                slotType = container.SlotTypes[slot];

                if (item.Consumable) {
                    var db = Manager.Database;

                    var trans = db.Conn.CreateTransaction();
                    var task = trans.ExecuteAsync();
                    task.ContinueWith(t => {
                        var success = !t.IsCanceled && t.Result;
                        if (!success ||
                            !Inventory.Execute(cInv)) // can result in the loss of an item if inv trans fails...
                        {
                            entity.ForceUpdate(slot);
                            return;
                        }

                        Activate(Manager.Logic.WorldTime, item, new Position {X = x, Y = y}, 0, 0, slot == 1);
                    });
                    task.ContinueWith(e =>
                            Log.Error(e.Exception.InnerException.ToString()),
                        TaskContinuationOptions.OnlyOnFaulted);
                    return;
                }
            }

            if (item.Consumable || item.SlotType == slotType)
                Activate(Manager.Logic.WorldTime, item, new Position {X = x, Y = y}, 0, 0, slot == 1);
            else
                Client.SendInvResult(1);
        }
    }

    private long _clientNextUse2;
    private double _coolDown;
    public int NextAttackMpRefill;

    private void Activate(RealmTime time, Item item, Position target, byte activateId,
        int clientTime, bool isAbility) {
        // todo new cd check
        var activate = item.ActivateEffects;

        if (activate == item.ActivateEffects) {
            MP -= item.MpCost;
            HP -= item.HpCost;
        }

        foreach (var eff in activate) {
            switch (eff.Effect) {
                case ActivateEffects.ConditionEffectSelf:
                    AEConditionEffectSelf(time, item, target, eff);
                    break;
                case ActivateEffects.ConditionEffectAura:
                    AEConditionEffectAura(time, item, target, eff);
                    break;
                case ActivateEffects.Heal:
                    AEHeal(time, item, target, eff);
                    break;
                case ActivateEffects.HealNova:
                    AEHealNova(time, item, target, eff);
                    break;
                case ActivateEffects.Magic:
                    AEMagic(time, item, target, eff);
                    break;
                case ActivateEffects.MagicNova:
                    AEMagicNova(time, item, target, eff);
                    break;
                case ActivateEffects.Teleport:
                    AETeleport(time, item, target, eff);
                    break;
                case ActivateEffects.FixedStat:
                    AEFixedStat(time, item, target, eff);
                    break;
                case ActivateEffects.IncrementStat:
                    AEIncrementStat(time, item, target, eff);
                    break;
                case ActivateEffects.Create:
                    AECreate(time, item, target, eff);
                    break;
                case ActivateEffects.UnlockPortal:
                    AEUnlockPortal(time, item, target, eff);
                    break;
                case ActivateEffects.UnlockEmote:
                    AEUnlockEmote(time, item, eff);
                    break;
                case ActivateEffects.UnlockSkin:
                    AEUnlockSkin(time, item, target, eff);
                    break;
                case ActivateEffects.Bloodstone:
                    AEBloodstone(time, item, target, eff);
                    break;
                case ActivateEffects.Totem:
                    AETotem(time, item, target, eff);
                    break;
                case ActivateEffects.Clock:
                    AEClock(time, item, target, eff);
                    break;
                case ActivateEffects.HitMultiplier:
                    AEHitMult(time, item, target, eff);
                    break;
                case ActivateEffects.DamageMultiplier:
                    AEDmgMult(time, item, target, eff);
                    break;
                default:
                    Log.Warn("Activate effect {0} not implemented.", eff.Effect);
                    break;
            }
        }
    }

    private void RefundItem(Item item, string message = "") {
        if (!string.IsNullOrWhiteSpace(message))
            SendError(message);

        var slot = Inventory.GetAvailableInventorySlot(item);

        if (slot != -1) {
            Inventory[slot] = item;
            return;
        }

        //todo
        //Manager.Database.AddGift(Client.Account, item);
        SendError($"Your inventory is full, and your {item} has been sent to a gift chest.");
    }


    private void AEUnlockEmote(RealmTime time, Item item, ActivateEffect eff) {
        var emotes = Client.Account.Emotes;
        if (!emotes.Contains(eff.Id)) {
            emotes.Add(eff.Id);
            Client.Account.Emotes = emotes;
            Client.Account.FlushAsync();
            SendInfo($"{eff.Id} ({eff.Id}) Emote unlocked successfully");
            return;
        }

        RefundItem(item, "You already have this emote!");
    }

    private void AEUnlockSkin(RealmTime time, Item item, Position target, ActivateEffect eff) {
        if (Owner is not Stash) {
            RefundItem(item, "You can only use this item in your stash.");
            return;
        }

        var acc = Client.Account;
        var ownedSkins = acc.Skins.ToList();

        if (!ownedSkins.Contains(eff.SkinType)) {
            ownedSkins.Add(eff.SkinType);
            acc.Skins = ownedSkins.ToArray();
            acc.FlushAsync();
            SendInfo("You've unlocked a new skin! Reconnect to reload changes.");
            return;
        }

        RefundItem(item, "You already have this skin!");
    }

    private void AEUnlockPortal(RealmTime time, Item item, Position target, ActivateEffect eff) {
        var gameData = Manager.Resources.GameData;

        // find locked portal
        var portals = Owner.StaticObjects.Values
            .Where(s => s is Portal && s.ObjectDesc.ObjectId.Equals(eff.LockedName) && s.DistSqr(this) <= 9)
            .Select(s => s as Portal);
        if (!portals.Any())
            return;
        var portal = portals.Aggregate(
            (curmin, x) => (curmin == null || x.DistSqr(this) < curmin.DistSqr(this) ? x : curmin));
        if (portal == null)
            return;

        // get proto of world
        ProtoWorld proto;
        if (!Manager.Resources.Worlds.Data.TryGetValue(eff.DungeonName, out proto)) {
            Log.Error("Unable to unlock portal. \"" + eff.DungeonName + "\" does not exist.");
            return;
        }

        if (proto.portals == null || proto.portals.Length < 1) {
            Log.Error("World is not associated with any portals.");
            return;
        }

        // create portal of unlocked world
        var portalType = (ushort) proto.portals[0];
        var uPortal = Resolve(Manager, portalType) as Portal;
        if (uPortal == null) {
            Log.Error("Error creating portal: {0}", portalType);
            return;
        }

        var portalDesc = gameData.Portals[portal.ObjectType];
        var uPortalDesc = gameData.Portals[portalType];

        // create world
        var world = proto.id < 0 ? Manager.GetWorld(proto.id) : Manager.AddWorld(new World(proto));
        uPortal.WorldInstance = world;

        // swap portals
        if (!portalDesc.NexusPortal || !Manager.Monitor.RemovePortal(portal))
            Owner.LeaveWorld(portal);
        uPortal.Move(portal.X, portal.Y);
        uPortal.Name = uPortalDesc.DisplayId;
        var uPortalPos = new Position {X = portal.X - .5f, Y = portal.Y - .5f};
        if (!uPortalDesc.NexusPortal || !Manager.Monitor.AddPortal(world.Id, uPortal, uPortalPos))
            Owner.EnterWorld(uPortal);

        // setup timeout
        if (!uPortalDesc.NexusPortal) {
            var timeoutTime = gameData.Portals[portalType].Timeout;
            Owner.Timers.Add(new WorldTimer(timeoutTime * 1000, (w, _) => w.LeaveWorld(uPortal)));
        }

        // announce
        foreach (var p in Owner.Players.Values) {
            p.Client.SendNotification(Id, $"Unlocked by {Name}", 0x00FF00);
        }

        foreach (var player in Owner.Players.Values)
            player.SendInfo($"{world.SBName} unlocked by {Name}");
    }

    private void AEBloodstone(RealmTime time, Item item, Position target, ActivateEffect eff) {
        var totalDmg = 0;
        var enemies = new List<Enemy>();
        Owner.AOE(target, eff.Radius, false, enemy => {
            enemies.Add(enemy as Enemy);
            totalDmg += ((Enemy) enemy).Damage(this, time, (int) eff.Amount);
        });

        var players = new List<Player>();
        this.AOE(eff.Radius, true, player => {
            if (player.HasConditionEffect(ConditionEffects.Sick)) 
                return;
                
            players.Add(player as Player);
            ActivateHealHp(player as Player, Math.Min(totalDmg, eff.TotalDamage));
        });

            
        Client.SendShowEffect(EffectType.Trail, Id, target.X, target.Y, 0, 0, 0xFF0000);
        Client.SendShowEffect(EffectType.Diffuse, Id, target.X, target.Y, target.X + eff.Radius, target.Y, 0xFF0000);
        if (enemies.Count <= 0) 
            return;
            
        for (var i = 0; i < 5; i++) {
            var a = enemies[Client.StaticRandom.Next(0, enemies.Count)];
            var b = players[Client.StaticRandom.Next(0, players.Count)];
            Client.SendShowEffect(EffectType.Flow, b.Id, a.X, a.Y, 0, 0, 0xFFFFFF);
        }
    }

    private void AETotem(RealmTime time, Item item, Position target, ActivateEffect eff) {
            
    }

    private void AEClock(RealmTime time, Item item, Position target, ActivateEffect eff) {
        var ticks = (byte) (eff.Amount * Manager.TPS);
        if (ticks <= 0)
            return;

        var oldPos = TryGetHistory(ticks);
        if (oldPos.HasValue && !TileOccupied(oldPos.Value.X, oldPos.Value.Y)) {
            Client.SendGoto(Id, oldPos.Value.X, oldPos.Value.Y);
        }

        var oldHp = TryGetHPHistory(ticks) ?? -1;
        var hpGain = Math.Max(0, oldHp - HP - item.HpCost);
        if (hpGain > 0) {
            Owner.Timers.Add(new WorldTimer(1000, (_, _) => {
                HP += hpGain;
                Client.SendShowEffect(EffectType.Potion, Id, 0f, 0f, 0f, 0f, 0xFFFFFF);
                Client.SendNotification(Id, "+" + hpGain, 0x00FF00);
            }));
        }
    }

    private void AEHitMult(RealmTime time, Item item, Position target, ActivateEffect eff) {
        HitMultiplier = eff.Amount;
        Owner.Timers.Add(new WorldTimer(eff.DurationMS, (_, _) => { HitMultiplier = 1; }));
    }

    private void AEDmgMult(RealmTime time, Item item, Position target, ActivateEffect eff) {
        DamageMultiplier = eff.Amount;
        Owner.Timers.Add(new WorldTimer(eff.DurationMS, (_, _) => { DamageMultiplier = 1; }));
    }

    private void AECreate(RealmTime time, Item item, Position target, ActivateEffect eff) {
        var gameData = Manager.Resources.GameData;

        if (!gameData.IdToObjectType.TryGetValue(eff.Id, out var objType) ||
            !gameData.Portals.ContainsKey(objType))
            return; // object not found, ignore

        var entity = Resolve(Manager, objType);
        var timeoutTime = gameData.Portals[objType].Timeout;

        entity.Move(X, Y);
        Owner.EnterWorld(entity);
        entity.AlwaysTick = true;

        ((Portal) entity).PlayerOpened = true;
        ((Portal) entity).Opener = Name;

        Owner.Timers.Add(new WorldTimer(timeoutTime * 1000, (world, _) => world.LeaveWorld(entity)));

        foreach (var p in Owner.Players.Values) {
            p.Client.SendNotification(Id, $"Opened by" + Name, 0xFF00FF00);
        }

        foreach (var player in Owner.Players.Values)
            player.SendInfo($"{gameData.Portals[objType].DungeonName} opened by {Name}");
    }

    private void AEIncrementStat(RealmTime time, Item item, Position target, ActivateEffect eff) {
        var idx = StatsManager.GetStatIndex((StatsType) eff.Stats);
        var statInfo = Manager.Resources.GameData.Classes[ObjectType].Stats;
        var itemName = string.IsNullOrEmpty(item.DisplayName) ? item.ObjectId : item.DisplayName;

        Stats.Base[idx] += (int) eff.Amount;
        if (Stats.Base[idx] < statInfo[idx].MaxValues[Tier - 1])
            SendInfo(
                $"{itemName} Consumed. {(statInfo[idx].MaxValues[Tier - 1] - Stats.Base[idx]) / eff.Amount} left to max.");
        else if (Stats.Base[idx] >= statInfo[idx].MaxValues[Tier - 1])
            SendInfo($"{itemName} Consumed. You are now maxed on this stat.");

        if (Stats.Base[idx] > statInfo[idx].MaxValues[Tier - 1])
            Stats.Base[idx] = statInfo[idx].MaxValues[Tier - 1];
    }

    private void AEFixedStat(RealmTime time, Item item, Position target, ActivateEffect eff) {
        var idx = StatsManager.GetStatIndex((StatsType) eff.Stats);
        Stats.Base[idx] = (int) eff.Amount;
    }

    private void AETeleport(RealmTime time, Item item, Position target, ActivateEffect eff) {
        TeleportPosition(time, target, true);
    }

    private void AEMagicNova(RealmTime time, Item item, Position target, ActivateEffect eff) {
        this.AOE(eff.Range, true, player =>
            ActivateHealMp(player as Player, (int) eff.Amount));
        foreach (var p in Owner.Players.Values)
            if (MathUtils.DistSqr(p.X, Y, X, Y) < VISIBILITY_RADIUS_SQR)
                p.Client.SendShowEffect(EffectType.AreaBlast, Id, eff.Range, eff.Range, 0, 0, 0xFFFFFF);
    }

    private void AEMagic(RealmTime time, Item item, Position target, ActivateEffect eff) {
        ActivateHealMp(this, (int) eff.Amount);
    }

    private void AEHealNova(RealmTime time, Item item, Position target, ActivateEffect eff) {
        if (!HasConditionEffect(ConditionEffects.Sick)) {
            var amount = eff.Amount;
            var range = eff.Range;

            this.AOE(range, true, player => {
                if (!player.HasConditionEffect(ConditionEffects.Sick))
                    ActivateHealHp(player as Player, (int) amount);
            });

            foreach (var p in Owner.Players.Values)
                if (MathUtils.DistSqr(p.X, Y, X, Y) < VISIBILITY_RADIUS_SQR)
                    p.Client.SendShowEffect(EffectType.AreaBlast, Id, eff.Range, eff.Range, 0, 0, 0xFFFFFF);
        }
    }

    private void AEHeal(RealmTime time, Item item, Position target, ActivateEffect eff) {
        if (!HasConditionEffect(ConditionEffects.Sick)) {
            ActivateHealHp(this, (int) eff.Amount);
        }
    }

    private void AEConditionEffectAura(RealmTime time, Item item, Position target, ActivateEffect eff) {
        var duration = eff.DurationMS;
        var range = eff.Range;

        this.AOE(range, true, player => {
            player.ApplyConditionEffect(new ConditionEffect() {
                Effect = eff.ConditionEffect.Value,
                DurationMS = duration
            });
        });
        foreach (var p in Owner.Players.Values) {
            if (MathUtils.DistSqr(p.X, Y, X, Y) < VISIBILITY_RADIUS_SQR)
                p.Client.SendShowEffect(EffectType.AreaBlast, Id, eff.Range, eff.Range, 0, 0, 0xFFFFFF);
        }
    }

    private void AEConditionEffectSelf(RealmTime time, Item item, Position target, ActivateEffect eff) {
        var duration = eff.DurationMS;

        ApplyConditionEffect(new ConditionEffect {
            Effect = eff.ConditionEffect.Value,
            DurationMS = duration
        });
        foreach (var p in Owner.Players.Values) {
            if (MathUtils.DistSqr(p.X, Y, X, Y) < VISIBILITY_RADIUS_SQR)
                p.Client.SendShowEffect(EffectType.AreaBlast, Id, eff.Range, eff.Range, 0, 0, 0xFFFFFF);
        }
    }
    
    private void ActivateHealHp(Player player, int amount) {
        var maxHp = player.Stats[0];
        var newHp = Math.Min(maxHp, player.HP + amount);
        if (newHp == player.HP)
            return;

        foreach (var p in Owner.Players.Values)
            if (MathUtils.DistSqr(p.X, p.Y, X, Y) < VISIBILITY_RADIUS_SQR) {
                p.Client.SendShowEffect(EffectType.Potion, Id, 0, 0, 0, 0, 0xFFFFFF);
                p.Client.SendNotification(player.Id, "+" + (newHp - player.HP), 0x00FF00);
            }

        player.HP = newHp;
    }

    private void ActivateHealMp(Player player, int amount) {
        var maxMp = player.Stats[1];
        var newMp = Math.Min(maxMp, player.MP + amount);
        if (newMp == player.MP)
            return;

        foreach (var p in Owner.Players.Values)
            if (MathUtils.DistSqr(p.X, p.Y, X, Y) < VISIBILITY_RADIUS_SQR) {
                p.Client.SendShowEffect(EffectType.Potion, Id, 0, 0, 0, 0, 0xFFFFFF);
                p.Client.SendNotification(player.Id, "+" + (newMp - player.MP), 0x9000FF);
            }

        player.MP = newMp;
    }
}