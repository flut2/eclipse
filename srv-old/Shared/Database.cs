using System;
using System.Collections.Generic;
using System.Linq;
using System.Security.Cryptography;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using System.Xml.Linq;
using StackExchange.Redis;
using Shared.resources;
using NLog;
using Newtonsoft.Json;

namespace Shared; 

public class Database : IDisposable
{
    private static readonly Logger Log = LogManager.GetCurrentClassLogger();

    private const int _lockTTL = 60;

    public int DatabaseIndex { get; }

    private ISManager _isManager;
    public static Resources Resources;

    private readonly ConnectionMultiplexer _redis;
    private readonly IDatabase _db;
    private readonly IServer _server;

    public IDatabase Conn => _db;
    public ISubscriber Sub { get; }

    public Database(string host, int port, string password, int dbIndex, Resources data)
    {
        Log.Info("Initializing Database...");
        Resources = data;

        DatabaseIndex = dbIndex;
        var conString = host + ":" + port + ",syncTimeout=60000";
        if (!string.IsNullOrWhiteSpace(password))
            conString += ",password=" + password;

        _redis = ConnectionMultiplexer.Connect(conString);
        _server = _redis.GetServer(_redis.GetEndPoints(true)[0]);
        _db = _redis.GetDatabase(DatabaseIndex);
        Sub = _redis.GetSubscriber();
    }

    public void SetISManager(ISManager isManager)
    {
        _isManager = isManager;
    }

    public void Dispose()
    {
        _redis.Dispose();
    }

    public LoginStatus Verify(string uuid, string password, out DbAccount acc)
    {
        acc = null;

        //check login
        var info = new DbLoginInfo(_db, uuid);
        if (info.IsNull)
            return LoginStatus.AccountNotExists;

        var userPass = Utils.SHA1(password + info.Salt);
        if (Convert.ToBase64String(userPass) != info.HashedPassword)
            return LoginStatus.InvalidCredentials;

        acc = new DbAccount(_db, info.AccountId);

        // make sure account has all skins if they are supposed to
        if (Resources.Settings.Accounts.SkinsUnlocked || acc.Rank >= 50)
        {
            acc.Skins = (from skin in Resources.GameData.Skins.Values
                where !skin.NoSkinSelect
                select skin.Type).ToArray();
        }

        return LoginStatus.OK;
    }

    // basic account locking functions
    public bool AcquireLock(DbAccount acc)
    {
        var tran = _db.CreateTransaction();

        var lockToken = Guid.NewGuid().ToString();

        var aKey = $"lock:{acc.AccountId}";
        tran.AddCondition(Condition.KeyNotExists(aKey));
        tran.StringSetAsync(aKey, lockToken, TimeSpan.FromSeconds(_lockTTL));

        var committed = tran.Execute();

        acc.LockToken = committed ? lockToken : null;
        return committed;
    }

    public TimeSpan? GetLockTime(DbAccount acc)
    {
        return _db.KeyTimeToLive($"lock:{acc.AccountId}");
    }

    public bool RenewLock(DbAccount acc)
    {
        var tran = _db.CreateTransaction();

        var aKey = $"lock:{acc.AccountId}";
        tran.AddCondition(Condition.StringEqual(aKey, acc.LockToken));
        tran.KeyExpireAsync(aKey, TimeSpan.FromSeconds(_lockTTL));

        return tran.Execute();
    }

    public void ReleaseLock(DbAccount acc)
    {
        var tran = _db.CreateTransaction();

        var aKey = $"lock:{acc.AccountId}";
        tran.AddCondition(Condition.StringEqual(aKey, acc.LockToken));
        tran.KeyDeleteAsync(aKey);

        tran.ExecuteAsync(CommandFlags.FireAndForget);
    }

    public bool AccountLockExists(int accId)
    {
        return _db.KeyExists($"lock:{accId}");
    }

    // abstracted account locking funcs
    private struct l : IDisposable
    {
        private Database db;
        private DbAccount acc;
        internal bool lockOk;

        public l(Database db, DbAccount acc)
        {
            this.db = db;
            this.acc = acc;
            lockOk = db.AcquireLock(acc);
        }

        public void Dispose()
        {
            if (lockOk)
                db.ReleaseLock(acc);
        }
    }

    public IDisposable Lock(DbAccount acc)
    {
        return new l(this, acc);
    }

    public bool LockOk(IDisposable l)
    {
        return ((l)l).lockOk;
    }

    public const string REG_LOCK = "regLock";
    public const string NAME_LOCK = "nameLock";

    public string AcquireLock(string key)
    {
        var lockToken = Guid.NewGuid().ToString();

        var tran = _db.CreateTransaction();
        tran.AddCondition(Condition.KeyNotExists(key));
        tran.StringSetAsync(key, lockToken, TimeSpan.FromSeconds(_lockTTL));

        return tran.Execute() ? lockToken : null;
    }

    public void ReleaseLock(string key, string token)
    {
        var tran = _db.CreateTransaction();
        tran.AddCondition(Condition.StringEqual(key, token));
        tran.KeyDeleteAsync(key);
        tran.Execute();
    }

    public bool RenameUUID(DbAccount acc, string newUuid, string lockToken)
    {
        string p = _db.HashGet("logins", acc.UUID.ToUpperInvariant());
        var trans = _db.CreateTransaction();
        trans.AddCondition(Condition.StringEqual(REG_LOCK, lockToken));
        trans.AddCondition(Condition.HashNotExists("logins", newUuid.ToUpperInvariant()));
        trans.HashDeleteAsync("logins", acc.UUID.ToUpperInvariant());
        trans.HashSetAsync("logins", newUuid.ToUpperInvariant(), p);
        if (!trans.Execute()) return false;

        acc.UUID = newUuid;
        acc.FlushAsync();
        return true;
    }

    public bool RenameIGN(DbAccount acc, string newName, string lockToken)
    {
        var trans = _db.CreateTransaction();
        trans.AddCondition(Condition.StringEqual(NAME_LOCK, lockToken));
        trans.HashDeleteAsync("names", acc.Name.ToUpperInvariant());
        trans.HashSetAsync("names", newName.ToUpperInvariant(), acc.AccountId.ToString());
        if (!trans.Execute()) return false;

        acc.Name = newName;
        acc.FlushAsync();
        return true;
    }
        
    private static RandomNumberGenerator gen = RNGCryptoServiceProvider.Create();

    public void ChangePassword(string uuid, string password)
    {
        var login = new DbLoginInfo(_db, uuid);

        var x = new byte[0x10];
        gen.GetNonZeroBytes(x);
        var salt = Convert.ToBase64String(x);
        var hash = Convert.ToBase64String(Utils.SHA1(password + salt));

        login.HashedPassword = hash;
        login.Salt = salt;
        login.Flush();
    }

    public RegisterStatus Register(string uuid, string password, string username, out DbAccount acc)
    {
        var newAccounts = Resources.Settings.Accounts;

        acc = null;
        if (!_db.HashSet("logins", uuid.ToUpperInvariant(), "{}", When.NotExists))
            return RegisterStatus.UsedName;

        var newAccId = (int)_db.StringIncrement("nextAccId");

        acc = new DbAccount(_db, newAccId)
        {
            UUID = uuid,
            Name = username,
            Admin = false,
            GuildId = 0,
            GuildRank = 0,
            VaultCount = newAccounts.VaultCount,
            MaxCharSlot = newAccounts.MaxCharSlot,
            RegTime = DateTime.Now,
            Credits = newAccounts.Gold,
            TotalCredits = newAccounts.Gold,
            PassResetToken = "",
            LastSeen = (Int32)(DateTime.UtcNow.Subtract(new DateTime(1970, 1, 1))).TotalSeconds
        };

        if (newAccounts.SkinsUnlocked)
        {
            acc.Skins = (from skin in Resources.GameData.Skins.Values
                where !skin.NoSkinSelect
                select skin.Type).ToArray();
        }

        acc.FlushAsync();

        var login = new DbLoginInfo(_db, uuid);

        var x = new byte[0x10];
        gen.GetNonZeroBytes(x);
        var salt = Convert.ToBase64String(x);
        var hash = Convert.ToBase64String(Utils.SHA1(password + salt));

        login.HashedPassword = hash;
        login.Salt = salt;
        login.AccountId = acc.AccountId;
        login.Flush();

        return RegisterStatus.OK;
    }

    public bool HasUUID(string uuid)
    {
        return _db.HashExists("logins", uuid.ToUpperInvariant());
    }

    public DbAccount GetAccount(int id, string field = null)
    {
        var ret = new DbAccount(_db, id, field);
        if (ret.IsNull) return null;
        return ret;
    }

    public DbAccount GetAccount(string uuid)
    {
        var info = new DbLoginInfo(_db, uuid);
        if (info.IsNull)
            return null;
        var ret = new DbAccount(_db, info.AccountId);
        if (ret.IsNull)
            return null;
        return ret;
    }

    public void LockAccount(DbAccount target, DbAccount acc, bool add)
    {
        var lockList = target.LockList.ToList();
        if (lockList.Contains(acc.AccountId) && add)
            return;

        if (add)
            lockList.Add(acc.AccountId);
        else
            lockList.Remove(acc.AccountId);

        target.LockList = lockList.ToArray();
        target.FlushAsync();
    }

    public void IgnoreAccount(DbAccount target, DbAccount acc, bool add)
    {
        var ignoreList = target.IgnoreList.ToList();
        if (ignoreList.Contains(acc.AccountId) && add)
            return;

        if (add)
            ignoreList.Add(acc.AccountId);
        else
            ignoreList.Remove(acc.AccountId);

        target.IgnoreList = ignoreList.ToArray();
        target.FlushAsync();
    }

    public void ReloadAccount(DbAccount acc)
    {
        acc.FlushAsync();
        acc.Reload();
    }

    public GuildCreateStatus CreateGuild(string guildName, out DbGuild guild)
    {
        guild = null;

        if (String.IsNullOrWhiteSpace(guildName))
            return GuildCreateStatus.InvalidName;

        // remove excessive whitespace
        var rgx = new Regex(@"\s+");
        guildName = rgx.Replace(guildName, " ");
        guildName = guildName.Trim();

        // check if valid
        rgx = new Regex(@"^[A-Za-z\s]{1,20}$");
        if (!rgx.IsMatch(guildName))
            return GuildCreateStatus.InvalidName;

        // add guild to guild list
        var newGuildId = (int)_db.StringIncrement("nextGuildId");
        if (!_db.HashSet("guilds", guildName.ToUpperInvariant(), newGuildId, When.NotExists))
            return GuildCreateStatus.UsedName;

        // create guild data structure
        guild = new DbGuild(_db, newGuildId)
        {
            Name = guildName,
            Level = 0,
        };

        // save
        guild.FlushAsync();

        return GuildCreateStatus.OK;
    }

    public DbGuild GetGuild(int id)
    {
        var ret = new DbGuild(_db, id);
        if (ret.IsNull) return null;
        return ret;
    }

    public AddGuildMemberStatus AddGuildMember(DbGuild guild, DbAccount acc, bool founder = false)
    {
        if (acc == null)
            return AddGuildMemberStatus.Error;

        if (acc.GuildId == guild.Id)
            return AddGuildMemberStatus.AlreadyInGuild;

        if (acc.GuildId > 0)
            return AddGuildMemberStatus.InAnotherGuild;

        lock (guild.MemberLock)
        {
            int guildSize;
            switch (guild.Level)
            {
                case (2):
                    guildSize = 60;
                    break;
                case (3):
                    guildSize = 75;
                    break;
                default:
                    guildSize = 50;
                    break;
            }

            // probably not best to lock this up but should be ok
            if (guild.Members.Length >= guildSize)
                return AddGuildMemberStatus.GuildFull;

            var members = guild.Members.ToList();
            if (members.Contains(acc.AccountId))
                return AddGuildMemberStatus.IsAMember; // this should not happen...
            members.Add(acc.AccountId);
            guild.Members = members.ToArray();
            guild.FlushAsync();
        }

        // set account guild info
        acc.GuildId = guild.Id;
        acc.GuildRank = (founder) ? 40 : 0;
        acc.FlushAsync();

        return AddGuildMemberStatus.OK;
    }

    public bool RemoveFromGuild(DbAccount acc)
    {
        var guild = GetGuild(acc.GuildId);

        if (guild == null)
            return false;

        List<int> members;
        lock (guild.MemberLock)
        {
            members = guild.Members.ToList();
            if (members.Contains(acc.AccountId))
            {
                members.Remove(acc.AccountId);
                guild.Members = members.ToArray();
                guild.FlushAsync();
            }
        }

        // remove guild name from guilds if there are no members
        if (members.Count <= 0)
            _db.HashDeleteAsync("guilds", guild.Name.ToUpperInvariant(), CommandFlags.FireAndForget);

        acc.GuildId = 0;
        acc.GuildRank = 0;
        acc.GuildFame = 0;
        acc.FlushAsync();
        return true;
    }

    public bool ChangeGuildRank(DbAccount acc, int rank)
    {
        if (acc.GuildId <= 0 || !(new Int16[] { 0, 10, 20, 30, 40 }).Any(r => r == rank))
            return false;

        acc.GuildRank = rank;
        acc.FlushAsync();
        return true;
    }

    public bool SetGuildBoard(DbGuild guild, string text)
    {
        if (guild.IsNull)
            return false;

        guild.Board = text;
        guild.FlushAsync();
        return true;
    }

    public bool ChangeGuildLevel(DbGuild guild, int level)
    {
        // supported guild levels
        if (level != 1 &&
            level != 2 &&
            level != 3)
            return false;

        guild.Level = level;
        guild.FlushAsync();
        return true;
    }

    public int ResolveId(string ign)
    {
        var val = (string)_db.HashGet("names", ign.ToUpperInvariant());
        if (val == null)
            return 0;
        return int.Parse(val);
    }

    public string ResolveIgn(int accId)
    {
        return _db.HashGet("account." + accId, "name");
    }

    public void PurchaseSkin(DbAccount acc, ushort skinType, int cost)
    {
        if (cost > 0)
            acc.TotalCredits = (int)_db.HashDecrement(acc.Key, "totalCredits", cost);
        acc.Credits = (int)_db.HashDecrement(acc.Key, "credits", cost);

        // not thread safe
        var ownedSkins = acc.Skins.ToList();
        ownedSkins.Add(skinType);
        acc.Skins = ownedSkins.ToArray();

        acc.FlushAsync();
    }

    public void AddToTreasury(int amount, ITransaction transaction = null)
    {
        if (transaction != null)
        {
            transaction.StringIncrementAsync("collectedTaxes", amount);
            return;
        }

        _db.StringIncrement("collectedTaxes", amount, CommandFlags.FireAndForget);
    }

    private static readonly Dictionary<CurrencyType, string[]> CurrencyKey = new()
    {
        { CurrencyType.Gold, new[] { "totalCredits", "credits" } },
    };

    public void UpdateCurrency(int accountId, int amount, CurrencyType currency, ITransaction transaction = null)
    {
        var trans = transaction ?? _db.CreateTransaction();

        var key = $"account.{accountId}";
        var fields = CurrencyKey[currency];

        if (amount > 0)
            trans.HashIncrementAsync(key, fields[0], amount);
        trans.HashIncrementAsync(key, fields[1], amount);

        if (transaction == null)
            trans.Execute();
    }

    public Task UpdateCurrency(DbAccount acc, int amount, CurrencyType currency, ITransaction transaction = null)
    {
        var trans = transaction ?? _db.CreateTransaction();

        var key = acc.Key;
        var fields = CurrencyKey[currency];

        // validate acc value before setting - TODO check guild fame
        var currentAmount = GetCurrencyAmount(acc, currency);
        if (currentAmount != null)
            trans.AddCondition(Condition.HashEqual(acc.Key, fields[1], currentAmount.Value));

        if (amount > 0)
            trans.HashIncrementAsync(key, fields[0], amount)
                .ContinueWith(t =>
                {
                    if (!t.IsCanceled)
                        UpdateAccountCurrency(acc, currency, (int)t.Result, true);
                });
        var task = trans.HashIncrementAsync(key, fields[1], amount)
            .ContinueWith(t =>
            {
                if (!t.IsCanceled)
                    UpdateAccountCurrency(acc, currency, (int)t.Result);
            });

        if (transaction == null)
            trans.Execute();

        return task;
    }

    private int? GetCurrencyAmount(DbAccount acc, CurrencyType currency)
    {
        switch (currency)
        {
            case CurrencyType.Gold:
                return acc.Credits;
            default:
                return null;
        }
    }

    private void UpdateAccountCurrency(DbAccount acc, CurrencyType type, int value, bool total = false)
    {
        switch (type)
        {
            case CurrencyType.Gold:
                if (total)
                    acc.TotalCredits = value;
                else
                    acc.Credits = value;
                break;
        }
    }

    public Task UpdateCredit(DbAccount acc, int amount, ITransaction transaction = null)
    {
        var trans = transaction ?? _db.CreateTransaction();

        if (amount > 0)
            trans.HashIncrementAsync(acc.Key, "totalCredits", amount)
                .ContinueWith(t =>
                {
                    if (!t.IsCanceled)
                        acc.TotalCredits = (int)t.Result;
                });

        var task = trans.HashIncrementAsync(acc.Key, "credits", amount)
            .ContinueWith(t =>
            {
                if (!t.IsCanceled)
                    acc.Credits = (int)t.Result;
            });

        if (transaction == null)
            trans.Execute();

        return task;
    }

    public int? CreateChest(DbAccount acc, ITransaction tran = null)
    {
        if (tran == null)
            return (int)_db.HashIncrement(acc.Key, "vaultCount");
        tran.HashIncrementAsync(acc.Key, "vaultCount");
        return null;
    }

    public int CreateGiftChest(DbAccount acc)
    {
        var id = (int)_db.HashIncrement(acc.Key, "giftCount");
        return id;
    }

    public IEnumerable<int> GetAliveCharacters(DbAccount acc)
    {
        foreach (var i in _db.SetMembers("alive." + acc.AccountId))
            yield return BitConverter.ToInt32(i, 0);
    }

    public IEnumerable<int> GetDeadCharacters(DbAccount acc)
    {
        foreach (var i in _db.ListRange("dead." + acc.AccountId, 0, int.MaxValue))
            yield return BitConverter.ToInt32(i, 0);
    }

    public bool IsAlive(DbChar character)
    {
        return _db.SetContains("alive." + character.Account.AccountId,
            BitConverter.GetBytes(character.CharId));
    }

    private ushort[] InitInventory(ushort[] givenItems)
    {
        var inv = Utils.ResizeArray(givenItems, 22);
        for (var i = givenItems.Length; i < inv.Length; i++)
            inv[i] = ushort.MaxValue;

        return inv;
    }

    public CreateStatus CreateCharacter(
        XmlData dat, DbAccount acc, ushort type, ushort skinType, out DbChar character)
    {
        var cls = dat.ObjectTypeToElement[type];

        if (_db.SetLength("alive." + acc.AccountId) >= acc.MaxCharSlot)
        {
            character = null;
            return CreateStatus.ReachCharLimit;
        }

        // check skin requirements
        if (skinType != 0)
        {
            var skinDesc = dat.Skins[skinType];
            if (!acc.Skins.Contains(skinType) ||
                skinDesc.PlayerClassType != type)
            {
                character = null;
                return CreateStatus.SkinUnavailable;
            }
        }

        var objDesc = dat.ObjectDescs[type];
        var playerDesc = dat.Classes[type];
        var unlockClass = (playerDesc.Unlock != null)
            ? playerDesc.Unlock.Type
            : null;

        var newId = (int)_db.HashIncrement(acc.Key, "nextCharId");

        character = new DbChar(acc, newId)
        {
            ObjectType = type,
            Items = InitInventory(playerDesc.Equipment),
            Stats = new[]
            {
                playerDesc.Stats[0].StartingValue,
                playerDesc.Stats[1].StartingValue,
                playerDesc.Stats[2].StartingValue,
                playerDesc.Stats[3].StartingValue,
                playerDesc.Stats[4].StartingValue,
                playerDesc.Stats[5].StartingValue,
                playerDesc.Stats[6].StartingValue,
                playerDesc.Stats[7].StartingValue,
                playerDesc.Stats[8].StartingValue,
                playerDesc.Stats[9].StartingValue,
                playerDesc.Stats[10].StartingValue,
                playerDesc.Stats[11].StartingValue,
                playerDesc.Stats[12].StartingValue
            },
            HP = playerDesc.Stats[0].StartingValue,
            MP = playerDesc.Stats[1].StartingValue,
            Tex1 = 0,
            Tex2 = 0,
            Skin = skinType,
            CreateTime = DateTime.Now,
            LastSeen = DateTime.Now
        };

        character.FlushAsync();
        _db.SetAdd("alive." + acc.AccountId, BitConverter.GetBytes(newId));
        return CreateStatus.OK;
    }

    public DbChar LoadCharacter(DbAccount acc, int charId)
    {
        var ret = new DbChar(acc, charId);
        if (ret.IsNull) return null;
        else return ret;
    }

    public DbChar LoadCharacter(int accId, int charId)
    {
        var acc = new DbAccount(_db, accId);
        if (acc.IsNull) return null;
        var ret = new DbChar(acc, charId);
        if (ret.IsNull) return null;
        else return ret;
    }

    public Task<bool> SaveCharacter(
        DbAccount acc, DbChar character, bool lockAcc)
    {
        var trans = _db.CreateTransaction();
        if (lockAcc)
            trans.AddCondition(Condition.StringEqual(
                $"lock:{acc.AccountId}", acc.LockToken));
        character.FlushAsync(trans);
        return trans.ExecuteAsync();
    }

    public void DeleteCharacter(DbAccount acc, int charId)
    {
        _db.KeyDeleteAsync("char." + acc.AccountId + "." + charId);
        var buff = BitConverter.GetBytes(charId);
        _db.SetRemoveAsync("alive." + acc.AccountId, buff);
        _db.ListRemoveAsync("dead." + acc.AccountId, buff);
    }

    public void Death(XmlData dat, DbAccount acc, DbChar character, string killer)
    {
        character.Dead = true;

        SaveCharacter(acc, character, acc.LockToken != null);

        var death = new DbDeath(acc, character.CharId)
        {
            ObjectType = character.ObjectType,
            Killer = killer,
            DeathTime = DateTime.UtcNow
        };
        death.FlushAsync();

        var idBuff = BitConverter.GetBytes(character.CharId);
        _db.SetRemoveAsync(
            "alive." + acc.AccountId, idBuff, CommandFlags.FireAndForget);
        _db.ListLeftPushAsync(
            "dead." + acc.AccountId, idBuff, When.Always, CommandFlags.FireAndForget);
    }

    public void RemoveAllGold()
    {
        var numAccounts = int.Parse(_db.StringGet("nextAccId"));
        for (var i = 1; i <= numAccounts; i++)
        {
            var acc = new DbAccount(_db, i);
            if (acc.Credits > 0 || acc.TotalCredits > 0)
            {
                Log.Info($"{acc.Name}:{acc.IP} has {acc.Credits} gold (total of {acc.TotalCredits}).");
                _db.HashSetAsync(acc.Key, "credits", 0, flags: CommandFlags.FireAndForget);
            }
        }
    }

    public void Wipe(XmlData dat)
    {
        var numAccounts = int.Parse(_db.StringGet("nextAccId"));
        for (var i = 1; i <= numAccounts; i++)
        {
            var acc = new DbAccount(_db, i);
            WipeAccount(acc, dat, "Langoliers");
        }

        // clear characters and death
        foreach (var key in _server.Keys(pattern: "char.*", database: DatabaseIndex))
            _db.KeyDeleteAsync(key, CommandFlags.FireAndForget);
        foreach (var key in _server.Keys(pattern: "death.*", database: DatabaseIndex))
            _db.KeyDeleteAsync(key, CommandFlags.FireAndForget);
        foreach (var key in _server.Keys(pattern: "alive.*", database: DatabaseIndex))
            _db.KeyDeleteAsync(key, CommandFlags.FireAndForget);
        foreach (var key in _server.Keys(pattern: "dead.*", database: DatabaseIndex))
            _db.KeyDeleteAsync(key, CommandFlags.FireAndForget);
        foreach (var key in _server.Keys(pattern: "account.*", database: DatabaseIndex))
        {
            _db.HashDeleteAsync(key, "firstDeath", CommandFlags.FireAndForget);
            _db.HashDeleteAsync(key, "nextCharId", CommandFlags.FireAndForget);
            _db.HashDeleteAsync(key, "nextPetId", CommandFlags.FireAndForget);
            _db.HashDeleteAsync(key, "nextQuestId", CommandFlags.FireAndForget);
            _db.HashDeleteAsync(key, "ignoreList", CommandFlags.FireAndForget);
        }

        // clear legends
        _db.KeyDeleteAsync("legends", CommandFlags.FireAndForget);

        // clear banned
        _db.KeyDeleteAsync("ips", CommandFlags.FireAndForget);

        // clear collectedTaxes
        _db.KeyDeleteAsync("collectedTaxes", CommandFlags.FireAndForget);

        // clear package purchases
        foreach (var key in _server.Keys(pattern: "package.*", database: DatabaseIndex))
            _db.KeyDeleteAsync(key, CommandFlags.FireAndForget);

        // clear muted
        foreach (var key in _server.Keys(pattern: "mutes:*", database: DatabaseIndex))
            _db.KeyDeleteAsync(key, CommandFlags.FireAndForget);

        // clear market
        _db.KeyDeleteAsync("market", CommandFlags.FireAndForget);
    }

    public void WipeAccount(DbAccount acc, XmlData dat, string killer)
    {
        // kill all characters on account
        var chars = GetAliveCharacters(acc);
        foreach (var @char in chars)
        {
            var c = new DbChar(acc, @char);
            Death(dat, acc, c, killer);
        }

        var accountSettings = Resources.Settings.Accounts;

        _db.HashSetAsync(acc.Key, "petYardType", 1, flags: CommandFlags.FireAndForget);
        _db.HashSetAsync(acc.Key, "vaultCount", accountSettings.VaultCount, flags: CommandFlags.FireAndForget);
        _db.HashDeleteAsync(acc.Key, "gifts", CommandFlags.FireAndForget);
        _db.HashDeleteAsync(acc.Key, "giftDatas", CommandFlags.FireAndForget);
        _db.HashSetAsync(acc.Key, "maxCharSlot", accountSettings.MaxCharSlot, flags: CommandFlags.FireAndForget);
        _db.HashSetAsync(acc.Key, "credits", 0, flags: CommandFlags.FireAndForget);
        _db.HashSetAsync(acc.Key, "totalCredits", 0, flags: CommandFlags.FireAndForget);
        _db.HashSetAsync(acc.Key, "unholyEssence", 0, flags: CommandFlags.FireAndForget);
        _db.HashSetAsync(acc.Key, "totalUnholyEssence", 0, flags: CommandFlags.FireAndForget);
        _db.HashSetAsync(acc.Key, "divineEssence", 0, flags: CommandFlags.FireAndForget);
        _db.HashSetAsync(acc.Key, "totalDivineEssence", 0, flags: CommandFlags.FireAndForget);
        _db.HashSetAsync(acc.Key, "fame", 0, flags: CommandFlags.FireAndForget);
        _db.HashSetAsync(acc.Key, "totalFame", 0, flags: CommandFlags.FireAndForget);
        _db.HashSetAsync(acc.Key, "tokens", 0, flags: CommandFlags.FireAndForget);
        _db.HashSetAsync(acc.Key, "totalTokens", 0, flags: CommandFlags.FireAndForget);
        _db.HashDeleteAsync(acc.Key, "skins", CommandFlags.FireAndForget);
        _db.HashDeleteAsync(acc.Key, "legend", CommandFlags.FireAndForget);
        _db.HashDeleteAsync(acc.Key, "banned", CommandFlags.FireAndForget);
        _db.HashDeleteAsync(acc.Key, "notes", CommandFlags.FireAndForget);
        _db.HashDeleteAsync(acc.Key, "hidden", CommandFlags.FireAndForget);
        _db.HashDeleteAsync(acc.Key, "glow", CommandFlags.FireAndForget);
        _db.HashDeleteAsync(acc.Key, "petList", CommandFlags.FireAndForget);
        _db.HashDeleteAsync(acc.Key, "banLiftTime", CommandFlags.FireAndForget);
        _db.HashDeleteAsync(acc.Key, "emotes", CommandFlags.FireAndForget);

        _db.KeyDeleteAsync($"vault.{acc.AccountId}", CommandFlags.FireAndForget);
    }

    public void LogAccountByIp(string ip, int accountId)
    {
        var abi = new DbIpInfo(_db, ip);

        if (!abi.IsNull)
            abi.Accounts.Add(accountId);
        else
            abi.Accounts = new HashSet<int> { accountId };

        abi.Flush();
    }

    public void Mute(string ip, TimeSpan? timeSpan = null)
    {
        _db.StringSetAsync($"mutes:{ip}", "", timeSpan);
    }

    public Task<bool> IsMuted(string ip)
    {
        return _db.KeyExistsAsync($"mutes:{ip}");
    }

    public void Ban(int accId, string reason = "", int liftTime = -1)
    {
        var acc = new DbAccount(_db, accId)
        {
            Banned = true,
            Notes = reason,
            BanLiftTime = liftTime
        };
        acc.FlushAsync();
    }

    public bool UnBan(int accId)
    {
        var acc = new DbAccount(_db, accId);
        if (acc.Banned)
        {
            acc.Banned = false;
            acc.FlushAsync();
            return true;
        }

        return false;
    }

    public void BanIp(string ip, string notes = "")
    {
        var abi = new DbIpInfo(_db, ip)
        {
            Banned = true,
            Notes = notes
        };
        abi.Flush();
    }

    public bool UnBanIp(string ip)
    {
        var abi = new DbIpInfo(_db, ip);
        if (!abi.IsNull && abi.Banned)
        {
            abi.Banned = false;
            abi.Flush();
            return true;
        }

        return false;
    }

    public bool IsIpBanned(string ip)
    {
        var abi = new DbIpInfo(_db, ip);
        return abi.Banned;
    }

    public Task<bool> MissedHitDetection(DbAccount acc, int misses)
    {
        var key = $"missedHitDetections:{acc.AccountId}";

        var task = _db.StringIncrementAsync(key, misses).ContinueWith(r =>
        {
            if (r.IsFaulted || r.Result < 40)
                return false;

            Log.Warn($"[Missed Detection ({acc.Name}:{acc.AccountId})] Kicked.");
            //Ban(acc.AccountId, "Auto ban for use of god mode.");
            //BanIp(acc.IP, "Auto ban for use of god mode.");
            return true;
        });
        _db.KeyExpireAsync(key, TimeSpan.FromSeconds(45), CommandFlags.FireAndForget);
        return task;
    }

    public void RegisterDiscord(string discordId, int accId)
    {
        _db.HashSetAsync($"discordAccount.{discordId}", accId, 0, When.Always, CommandFlags.FireAndForget);
        _db.HashSetAsync($"account.{accId}", "discordId", discordId, When.Always, CommandFlags.FireAndForget);
    }

    public bool UnregisterDiscord(string discordId, int accId)
    {
        if (!_db.HashExists($"discordAccount.{discordId}", accId))
            return false;

        _db.HashDeleteAsync($"discordAccount.{discordId}", accId, CommandFlags.FireAndForget);
        _db.HashDeleteAsync($"account.{accId}", "discordId", CommandFlags.FireAndForget);
        return true;
    }

    public void IncrementHashField(string key, string hashField)
    {
        _db.HashIncrement(key, hashField);
    }

    public int GetCharacterHashField(DbChar character, string hashField)
    {
        return (int)_db.HashGet("char." + character.Account.AccountId + "." + character.CharId, hashField);
    }

    public int GetAccountHashField(DbAccount account, string hashField)
    {
        return (int)_db.HashGet("account." + account.AccountId, hashField);
    }
}