using System.Globalization;
using Shared;
using GameServer.logic;
using GameServer.realm.worlds;
using GameServer.realm.worlds.logic;
using Newtonsoft.Json;
using NLog;
using wServer.realm;

namespace GameServer.realm.entities.player; 

internal interface IPlayer {
    void Damage(int dmg, Entity src, bool noDef);
    bool IsVisibleToEnemy();
}

public partial class Player : Character, IContainer, IPlayer {
    private new static readonly Logger Log = LogManager.GetCurrentClassLogger();

    private readonly Client _client;
    public Client Client => _client;

    //Stats
    private readonly SV<int> _accountId;

    public int AccountId {
        get => _accountId.GetValue();
        set => _accountId.SetValue(value);
    }

    private readonly SV<string> _guild;

    public string Guild {
        get => _guild.GetValue();
        set => _guild.SetValue(value);
    }

    private readonly SV<sbyte> _guildRank;

    public sbyte GuildRank {
        get => _guildRank.GetValue();
        set => _guildRank.SetValue(value);
    }

    private readonly SV<int> _credits;

    public int Credits {
        get => _credits.GetValue();
        set => _credits.SetValue(value);
    }
    
    private readonly SV<ushort> _texture1;

    public ushort Texture1 {
        get => _texture1.GetValue();
        set => _texture1.SetValue(value);
    }

    private readonly SV<ushort> _texture2;

    public ushort Texture2 {
        get => _texture2.GetValue();
        set => _texture2.SetValue(value);
    }

    private ushort _originalSkin;
    private readonly SV<ushort> _skin;

    public ushort Skin {
        get => _skin.GetValue();
        set => _skin.SetValue(value);
    }

    private readonly SV<int> _mp;

    public int MP {
        get => _mp.GetValue();
        set => _mp.SetValue(value);
    }

    private readonly SV<int> _rank;

    public int Rank {
        get => _rank.GetValue();
        set => _rank.SetValue(value);
    }

    private readonly SV<int> _admin;

    public int Admin {
        get => _admin.GetValue();
        set => _admin.SetValue(value);
    }

    private readonly SV<int> _tier;

    public int Tier {
        get => _tier.GetValue();
        set => _tier.SetValue(value);
    }
        
    private readonly SV<float> _hitMult;

    public float HitMultiplier {
        get => _hitMult.GetValue();
        set => _hitMult.SetValue(value);
    }
        
    private readonly SV<float> _dmgMult;

    public float DamageMultiplier {
        get => _dmgMult.GetValue();
        set => _dmgMult.SetValue(value);
    }
    
    public int? GuildInvite { get; set; }
    public bool Muted { get; set; }

    public RInventory DbLink { get; private set; }
    public int[] SlotTypes { get; private set; }
    public Inventory Inventory { get; private set; }

    public readonly StatsManager Stats;

    protected override void ExportStats(IDictionary<StatsType, object> stats) {
        base.ExportStats(stats);
        stats[StatsType.AccountId] = AccountId;
        stats[StatsType.Guild] = Guild;
        stats[StatsType.GuildRank] = GuildRank;
        stats[StatsType.Texture1] = Texture1;
        stats[StatsType.Texture2] = Texture2;
        stats[StatsType.Texture] = Skin;
        stats[StatsType.MP] = MP;

        stats[StatsType.Inv0] = Inventory[0]?.ObjectType ?? ushort.MaxValue;
        stats[StatsType.Inv1] = Inventory[1]?.ObjectType ?? ushort.MaxValue;
        stats[StatsType.Inv2] = Inventory[2]?.ObjectType ?? ushort.MaxValue;
        stats[StatsType.Inv3] = Inventory[3]?.ObjectType ?? ushort.MaxValue;
        stats[StatsType.Inv4] = Inventory[4]?.ObjectType ?? ushort.MaxValue;
        stats[StatsType.Inv5] = Inventory[5]?.ObjectType ?? ushort.MaxValue;
        stats[StatsType.Inv6] = Inventory[6]?.ObjectType ?? ushort.MaxValue;
        stats[StatsType.Inv7] = Inventory[7]?.ObjectType ?? ushort.MaxValue;
        stats[StatsType.Inv8] = Inventory[8]?.ObjectType ?? ushort.MaxValue;
        stats[StatsType.Inv9] = Inventory[9]?.ObjectType ?? ushort.MaxValue;
        stats[StatsType.Inv10] = Inventory[10]?.ObjectType ?? ushort.MaxValue;
        stats[StatsType.Inv11] = Inventory[11]?.ObjectType ?? ushort.MaxValue;
        stats[StatsType.Inv12] = Inventory[12]?.ObjectType ?? ushort.MaxValue;
        stats[StatsType.Inv13] = Inventory[13]?.ObjectType ?? ushort.MaxValue;
        stats[StatsType.Inv14] = Inventory[14]?.ObjectType ?? ushort.MaxValue;
        stats[StatsType.Inv15] = Inventory[15]?.ObjectType ?? ushort.MaxValue;
        stats[StatsType.Inv16] = Inventory[16]?.ObjectType ?? ushort.MaxValue;
        stats[StatsType.Inv17] = Inventory[17]?.ObjectType ?? ushort.MaxValue;
        stats[StatsType.Inv18] = Inventory[18]?.ObjectType ?? ushort.MaxValue;
        stats[StatsType.Inv19] = Inventory[19]?.ObjectType ?? ushort.MaxValue;

        Stats.ExportStatData(stats);

        stats[StatsType.HitMultiplier] = HitMultiplier;
        stats[StatsType.DamageMultiplier] = DamageMultiplier;
        stats[StatsType.Tier] = Tier;
    }

    public void SaveToCharacter() {
        var chr = _client.Character;
        chr.HP = Math.Max(1, HP);
        chr.MP = MP;
        chr.Stats = Stats.Base.GetStats();
        chr.Tex1 = Texture1;
        chr.Tex2 = Texture2;
        chr.Skin = _originalSkin;
        chr.LastSeen = DateTime.Now;
        chr.Items = Inventory.GetItemTypes();
        chr.Tier = Tier;
    }

    public Player(Client client, bool saveInventory = true)
        : base(client.Manager, client.Character.ObjectType) {
        var settings = Manager.Resources.Settings;
        var gameData = Manager.Resources.GameData;

        _client = client;

        // found in player.update partial
        Sight = new Sight(this);
        _clientEntities = new UpdatedSet(this);

        _accountId = new SV<int>(this, StatsType.AccountId, client.Account.AccountId, true);
        _guild = new SV<string>(this, StatsType.Guild, "");
        _admin = new SV<int>(this, StatsType.None, 0);
        _guildRank = new SV<sbyte>(this, StatsType.GuildRank, -1);
        _texture1 = new SV<ushort>(this, StatsType.Texture1, (ushort) client.Character.Tex1);
        _texture2 = new SV<ushort>(this, StatsType.Texture2, (ushort) client.Character.Tex2);
        _skin = new SV<ushort>(this, StatsType.Texture, 0);
        _mp = new SV<int>(this, StatsType.MP, client.Character.MP);
        _tier = new SV<int>(this, StatsType.Tier, 1, true);
        _hitMult = new SV<float>(this, StatsType.HitMultiplier, 1, true);
        _dmgMult = new SV<float>(this, StatsType.DamageMultiplier, 1, true);

        Name = client.Account.Name;
        HP = client.Character.HP;
        ConditionEffects = 0;

        var s = (ushort) client.Character.Skin;
        if (gameData.Skins.Keys.Contains(s)) {
            SetDefaultSkin(s);
            SetDefaultSize((ushort) gameData.Skins[s].Size);
        }

        var guild = Manager.Database.GetGuild(client.Account.GuildId);
        if (guild?.Name != null) {
            Guild = guild.Name;
            GuildRank = (sbyte) client.Account.GuildRank;
        }

        // inventory setup
        DbLink = new DbCharInv(Client.Account, Client.Character.CharId);
        Inventory = new Inventory(this,
            Utils.ResizeArray(
                (DbLink as DbCharInv).Items
                .Select(_ => (_ == ushort.MaxValue || !gameData.Items.ContainsKey(_)) ? null : gameData.Items[_])
                .ToArray(),
                22));

        if (!saveInventory)
            DbLink = null;

        Inventory.InventoryChanged += (_, e) => {
            Stats.ReCalculateValues(e);
        };

        SlotTypes = Utils.ResizeArray(
            gameData.Classes[ObjectType].SlotTypes,
            22);
        Stats = new StatsManager(this);

        // override size
        if (Client.Account.Size > 0)
            Size = (ushort) Client.Account.Size;

        Manager.Database.IsMuted(client.IP)
            .ContinueWith(t => { Muted = !Client.Account.Admin && t.IsCompleted && t.Result; });

        Admin = client.Account.Admin ? 1 : 0;

        LoadAbilities();
    }

    private byte[,] tiles;

    public Entity SpectateTarget { get; set; }
    public bool IsControlling => SpectateTarget != null && !(SpectateTarget is Player);


    public override void Init(World owner) {
        var x = 0;
        var y = 0;
        var spawnRegions = owner.GetSpawnPoints();
        if (spawnRegions.Any()) {
            var rand = new Random();
            var sRegion = spawnRegions.ElementAt(rand.Next(0, spawnRegions.Length));
            x = sRegion.Key.X;
            y = sRegion.Key.Y;
        }

        Move(x + 0.5f, y + 0.5f);
        tiles = new byte[owner.Map.Width, owner.Map.Height];

        SetNewbiePeriod();
        base.Init(owner);
    }


    public override void Tick(RealmTime time) {
        if (!KeepAlive(time))
            return;

        CheckTradeTimeout(time);

        HandleRegen(time);
        HandleEffects(time);

        base.Tick(time);
        if (_hpHistory != null)
            _hpHistory[++_hpIdx] = HP;

        SendUpdate(time);
        SendNewTick(time);

        if (HP <= 0)
            Death("Unknown", rekt: true);
    }

    private float _hpRegenCounter;
    private float _mpRegenCounter;

    private void HandleRegen(RealmTime time) {
        // hp regen
        if (HP == Stats[StatsManager.HEALTH_STAT] || !CanHpRegen())
            _hpRegenCounter = 0;
        else {
            _hpRegenCounter += Stats.GetHpRegen() * time.ElapsedUsDelta / (1000f * 1000f);
            var regen = (int) _hpRegenCounter;
            if (regen > 0) {
                HP = Math.Min(Stats[0], HP + regen);
                _hpRegenCounter -= regen;
            }
        }

        // mp regen
        if (MP == Stats[1])
            _mpRegenCounter = 0;
        else {
            _mpRegenCounter += Stats.GetMpRegen() * time.ElapsedUsDelta / (1000f * 1000f);
            var regen = (int) _mpRegenCounter;
            if (regen > 0) {
                MP = Math.Min(Stats[StatsManager.MANA_STAT], MP + regen);
                _mpRegenCounter -= regen;
            }
        }
    }

    public void TeleportPosition(RealmTime time, float x, float y, bool ignoreRestrictions = false,
        bool removeNegative = false) {
        TeleportPosition(time, new Position() {X = x, Y = y}, ignoreRestrictions, removeNegative);
    }

    public void TeleportPosition(RealmTime time, Position position, bool ignoreRestrictions = false,
        bool removeNegative = false) {
        if (!ignoreRestrictions) {
            if (!TPCooledDown()) {
                SendError("Too soon to teleport again!");
                return;
            }

            SetTPDisabledPeriod();
            SetNewbiePeriod();
        }

        if (removeNegative) {
            ApplyConditionEffect(NegativeEffs);
        }

        Client.SendGoto(Id, position.X, position.Y);
        foreach (var plr in Owner.Players.Values)
            plr.Client.SendShowEffect(EffectType.Teleport, Id, position.X, position.Y, 0, 0, 0xFFFFFF);
    }

    public void Teleport(RealmTime time, int objId, bool ignoreRestrictions = false) {
        var obj = Owner.GetEntity(objId);
        if (obj == null) {
            SendError("Target does not exist.");
            return;
        }

        if (!ignoreRestrictions) {
            if (Id == objId) {
                SendInfo("You are already at yourself, and always will be!");
                return;
            }

            if (!Owner.AllowTeleport) {
                SendError("Cannot teleport here.");
                return;
            }

            if (obj is not Player) {
                SendError("Can only teleport to players.");
                return;
            }
        }

        TeleportPosition(time, obj.X, obj.Y, ignoreRestrictions);
    }

    public bool IsInvulnerable() {
        if (HasConditionEffect(ConditionEffects.Invulnerable))
            return true;
        return false;
    }

    public override bool HitByProjectile(Projectile projectile, RealmTime time) {
        if (projectile.ProjectileOwner is Player || IsInvulnerable())
            return false;

        var dmg = (int)(Stats.GetPhysicalDamage(projectile.PhysDamage, this) + 
                        Stats.GetMagicDamage(projectile.MagicDamage, this) +
                        Stats.GetTrueDamage(projectile.TrueDamage));
        HP -= dmg;

        ApplyConditionEffect(projectile.ProjDesc.Effects);

        foreach (var p in Owner.Players.Values)
            if (MathUtils.DistSqr(X, Y, p.X, p.Y) < 16 * 16)
                p.Client.SendDamage(Id, projectile.ConditionEffects, (ushort) dmg, HP <= 0, projectile.BulletId,
                    projectile.ProjectileOwner.Self.Id);

        if (HP <= 0)
            Death(projectile.ProjectileOwner.Self.ObjectDesc.DisplayId ??
                  projectile.ProjectileOwner.Self.ObjectDesc.ObjectId,
                projectile.ProjectileOwner.Self);

        return base.HitByProjectile(projectile, time);
    }

    public void Damage(int dmg, Entity src, bool noDef = false) {
        if (IsInvulnerable())
            return;

        dmg = (int)Stats.GetPhysicalDamage(dmg, this);
        HP -= dmg;

        foreach (var p in Owner.Players.Values)
            if (MathUtils.DistSqr(X, Y, p.X, p.Y) < 16 * 16)
                p.Client.SendDamage(Id, 0, (ushort) dmg, HP <= 0, 0, src.Id);

        if (HP <= 0)
            Death(src.ObjectDesc.DisplayId ??
                  src.ObjectDesc.ObjectId,
                src);
    }

    private void GenerateGravestone(bool phantomDeath = false) {
        ushort objType;
        int time;
        switch (Tier) {
            case 3:
                objType = 0x116;
                time = 600000;
                break;
            case 2:
                objType = 0x115;
                time = 600000;
                break;
            default:
                objType = 0x114;
                time = 300000;
                break;
        }

        var obj = new StaticObject(Manager, objType, time, true, true, false);
        obj.Move(X, Y);
        obj.Name = (!phantomDeath) ? Name : $"{Name} got rekt";
        Owner.EnterWorld(obj);
    }

    private bool NonPermaKillEnemy(Entity entity, string killer) {
        if (entity == null) {
            return false;
        }

        if ((!entity.Spawned && !entity.DevSpawned) && entity.Controller == null)
            return false;

        //foreach (var player in Owner.Players.Values)
        //    player.SendInfo(Name + " was sent home crying by a phantom " + killer);

        GenerateGravestone(true);
        ReconnectToRetrieve();
        return true;
    }

    private bool Rekted(bool rekt) {
        if (!rekt)
            return false;

        GenerateGravestone(true);
        ReconnectToRetrieve();
        return true;
    }

    private bool TestWorld(string killer) {
        GenerateGravestone();
        ReconnectToRetrieve();
        return true;
    }

    private bool _dead;

    private bool Resurrection() {
        for (var i = 0; i < 6; i++) {
            var item = Inventory[i];

            if (item == null || !item.Resurrects)
                continue;

            Inventory[i] = null;
            foreach (var player in Owner.Players.Values)
                player.SendInfo(
                    $"{Name}'s {item.DisplayName} breaks and they disappear");

            ReconnectToRetrieve();
            return true;
        }

        return false;
    }

    private void ReconnectToRetrieve() {
        HP = 1;
        _client.Reconnect("the Retrieve", World.Retrieve);
    }

    private void AnnounceDeath(string killer) {
        var playerDesc = Manager.Resources.GameData.Classes[ObjectType];
        var maxed = playerDesc.Stats.Where((t, i) => Stats.Base[i] >= t.MaxValues[Tier - 1] && (i < 8 || i > 18))
            .Count();
        var notableDeath = maxed >= 6;

        List<string> deathmsgVariations = new();

        string[] commonDeathMsgs = {
            $"was slain by {killer}", $"was killed by {killer}", $"died to {killer}", $"was massacred by {killer}",
            $"couldn't handle {killer}", $"was taken care of by {killer}", $"was engraved 6 feet under by {killer}",
            $"expired thanks to {killer}", $"departed when fighting {killer}",
            $"is no more thanks to {killer}", $"couldn't take care of {killer}", $"couldn't kill {killer}",
            $"was too kind when facing {killer}", $"got the worst death message variation when dueling {killer}",
            $"was permanently eliminated by {killer}", $"got banished from the world of the living by {killer}",
            $"proved Oryx's point by dying to {killer}", $"got smashed by {killer}", $"was deleted by {killer}",
            $"lost the life or death duel against {killer}"
        };
        deathmsgVariations.AddRange(commonDeathMsgs);
        if (notableDeath) {
            #region Notable Death death message variations

            deathmsgVariations.AddRange(new[] {
                $"took the L against {killer}",
                $"rage quit thanks to {killer}",
                $"left the server thanks to {killer}",
                $"was timed out by {killer}",
                $"has a skill issue and can't kill {killer}",
                $"is trippin', {killer}!",
                $"got soft wiped by {killer}",
                $"was weaker than {killer}",
                $"got slam dunked by {killer}",
                $"lost all that they had thanks to {killer}"
            });

            #endregion
        }

        var deathMessage =
            $"{Name} [{maxed}/11] {deathmsgVariations.PickRandom()}";

        // notable deaths
        if (notableDeath && !Client.Account.Admin) {
            foreach (var w in Manager.Worlds.Values)
            foreach (var p in w.Players.Values)
                p.SendInfo(deathMessage);
            return;
        }

        var pGuild = Client.Account.GuildId;


        foreach (var i in Owner.Players.Values) {
            i.SendInfo(deathMessage);
        }
    }

    public void Death(string killer, Entity entity = null, MapTile? tile = null, bool rekt = false) {
        if (_dead)
            return;

        if (tile != null) {
            rekt = true;
        }

        _dead = true;

        if (Rekted(rekt))
            return;
        if (NonPermaKillEnemy(entity, killer))
            return;
        if (TestWorld(killer))
            return;
        if (Resurrection())
            return;

        SaveToCharacter();
        Manager.Database.Death(Manager.Resources.GameData, _client.Account,
            _client.Character, killer);

        GenerateGravestone();
        AnnounceDeath(killer);

        _client.SendDeath(AccountId, _client.Character.CharId, killer);

        Owner.Timers.Add(new WorldTimer(1000, (w, t) => {
            if (_client.Player != this)
                return;

            _client.Disconnect();
        }));
    }

    private bool CheckLimitedWorlds(World world) {
        return true;
    }

    public void Reconnect(World world) {
        if (world == null)
            SendError("This world does not exist.");
        else {
            if (!CheckLimitedWorlds(world))
                return;

            Client.Reconnect(world.Name, world.Id);
        }
    }

    public void Reconnect(object portal, World world) {
        ((Portal) portal).WorldInstanceSet -= Reconnect;

        if (world == null)
            SendError("This world does not exist.");
        else {
            if (!CheckLimitedWorlds(world))
                return;

            Client.Reconnect(world.Name, world.Id);
        }
    }

    private void ShowNotification(string notif, uint color = 0xFF00FF00) {
        if (Owner is null) {
            return;
        }

        foreach (var p in Owner.Players.Values)
            if (MathUtils.DistSqr(X, Y, p.X, p.Y) < 16 * 16)
                p.Client.SendNotification(Id, notif, color);
    }

    public int GetCurrency(CurrencyType currency) {
        switch (currency) {
            case CurrencyType.Gold:
                return Credits;
            default:
                return 0;
        }
    }

    public void SetCurrency(CurrencyType currency, int amount) {
        switch (currency) {
            case CurrencyType.Gold:
                Credits = amount;
                break;
        }
    }

    public override void Move(float x, float y) {
        base.Move(x, y);
        if ((int) X != Sight.LastX || (int) Y != Sight.LastY)
            Sight.UpdateCount++;
    }

    public override void Dispose() {
        base.Dispose();
        DisposeUpdate();
    }

    // allow other admins to see hidden people
    public override bool CanBeSeenBy(Player player) {
        if (Client?.Account != null && Client.Account.Hidden) {
            return player.Admin != 0;
        }
        else {
            return true;
        }
    }

    public void SetDefaultSkin(ushort skin) {
        _originalSkin = skin;
        Skin = skin;
    }

    public void RestoreDefaultSkin() {
        Skin = _originalSkin;
    }
}