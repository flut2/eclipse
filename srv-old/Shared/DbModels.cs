using System.Text;
using Shared.resources;
using Newtonsoft.Json;
using StackExchange.Redis;

namespace Shared; 

public abstract class RedisObject
{

    //Note do not modify returning buffer
    private Dictionary<RedisValue, KeyValuePair<byte[], bool>> _entries;

    protected void Init(IDatabase db, string key, string field = null)
    {
        Key = key;
        Database = db;

        if (field == null)
            _entries = db.HashGetAll(key)
                .ToDictionary(
                    x => x.Name,
                    x => new KeyValuePair<byte[], bool>(x.Value, false));
        else
        {
            var entry = new[] { new HashEntry(field, db.HashGet(key, field)) };
            _entries = entry.ToDictionary(x => x.Name,
                x => new KeyValuePair<byte[], bool>(x.Value, false));
        }
    }

    public IDatabase Database { get; private set; }
    public string Key { get; private set; }

    public IEnumerable<RedisValue> AllKeys => _entries.Keys;

    public bool IsNull => _entries.Count == 0;

    protected byte[] GetValueRaw(RedisValue key)
    {
        KeyValuePair<byte[], bool> val;
        if (!_entries.TryGetValue(key, out val))
            return null;

        if (val.Key == null)
            return null;

        return (byte[])val.Key.Clone();
    }

    protected T GetValue<T>(RedisValue key, T def = default)
    {
        KeyValuePair<byte[], bool> val;
        if (!_entries.TryGetValue(key, out val) || val.Key == null)
            return def;

        if (typeof(T) == typeof(int))
            return (T)(object)int.Parse(Encoding.UTF8.GetString(val.Key));

        if (typeof(T) == typeof(uint))
            return (T)(object)uint.Parse(Encoding.UTF8.GetString(val.Key));

        if (typeof(T) == typeof(ushort))
            return (T)(object)ushort.Parse(Encoding.UTF8.GetString(val.Key));

        if (typeof(T) == typeof(bool))
            return (T)(object)(val.Key[0] != 0);

        if (typeof(T) == typeof(DateTime))
            return (T)(object)DateTime.FromBinary(BitConverter.ToInt64(val.Key, 0));

        if (typeof(T) == typeof(byte[]))
            return (T)(object)val.Key;

        if (typeof(T) == typeof(ushort[]))
        {
            var ret = new ushort[val.Key.Length / 2];
            Buffer.BlockCopy(val.Key, 0, ret, 0, val.Key.Length);
            return (T)(object)ret;
        }

        if (typeof(T) == typeof(int[]) ||
            typeof(T) == typeof(uint[]))
        {
            var ret = new int[val.Key.Length / 4];
            Buffer.BlockCopy(val.Key, 0, ret, 0, val.Key.Length);
            return (T)(object)ret;
        }
            
        if (typeof(T) == typeof(HashSet<int>))
        {
            var ret = new HashSet<int>();
            var arr = new int[val.Key.Length / 4];
            Buffer.BlockCopy(val.Key, 0, arr, 0, val.Key.Length);
            for (var i = 0; i < arr.Length; i++)
                ret.Add(arr[i]);
            return (T)(object)ret;
        }

        if (typeof(T) == typeof(string))
            return (T)(object)Encoding.UTF8.GetString(val.Key);

        throw new NotSupportedException();
    }

    protected void SetValue<T>(RedisValue key, T val)
    {
        byte[] buff;
        if (typeof(T) == typeof(int) || typeof(T) == typeof(uint) ||
            typeof(T) == typeof(ushort) || typeof(T) == typeof(string))
            buff = Encoding.UTF8.GetBytes(val.ToString());

        else if (typeof(T) == typeof(bool))
            buff = new[] { (byte)((bool)(object)val ? 1 : 0) };

        else if (typeof(T) == typeof(DateTime))
            buff = BitConverter.GetBytes(((DateTime)(object)val).ToBinary());

        else if (typeof(T) == typeof(byte[]))
            buff = (byte[])(object)val;

        else if (typeof(T) == typeof(ushort[]))
        {
            var v = (ushort[])(object)val;
            buff = new byte[v.Length * 2];
            Buffer.BlockCopy(v, 0, buff, 0, buff.Length);
        }

        else if (typeof(T) == typeof(int[]) ||
                 typeof(T) == typeof(uint[]))
        {
            var v = (int[])(object)val;
            buff = new byte[v.Length * 4];
            Buffer.BlockCopy(v, 0, buff, 0, buff.Length);
        }

        else if (typeof(T) == typeof(HashSet<int>))
        {
            var v = (HashSet<int>)(object)val;
            var arr = new int[v.Count];
            var i = 0;
            foreach (var n in v)
            {
                arr[i] = n;
                i++;
            }
            buff = new byte[arr.Length * 4];
            Buffer.BlockCopy(arr, 0, buff, 0, buff.Length);
        }

        else
            throw new NotSupportedException();

        if (!_entries.ContainsKey(Key) || _entries[Key].Key == null || !buff.SequenceEqual(_entries[Key].Key))
            _entries[key] = new KeyValuePair<byte[], bool>(buff, true);
    }

    private List<HashEntry> _update;

    public Task FlushAsync(ITransaction transaction = null)
    {
        ReadyFlush();
        return transaction == null
            ? Database.HashSetAsync(Key, _update.ToArray())
            : transaction.HashSetAsync(Key, _update.ToArray());
    }

    private void ReadyFlush()
    {
        if (_update == null)
            _update = new List<HashEntry>();
        _update.Clear();

        foreach (var name in _entries.Keys)
            if (_entries[name].Value)
                _update.Add(new HashEntry(name, _entries[name].Key));

        foreach (var update in _update)
            _entries[update.Name] = new KeyValuePair<byte[], bool>(_entries[update.Name].Key, false);
    }

    public async Task ReloadAsync(ITransaction trans = null, string field = null)
    {
        if (field != null && _entries != null)
        {
            var tf = trans != null ? trans.HashGetAsync(Key, field) : Database.HashGetAsync(Key, field);

            try
            {
                await tf;
                _entries[field] = new KeyValuePair<byte[], bool>(
                    tf.Result, false);
            }
            catch
            {
            }

            return;
        }

        var t = trans != null ? trans.HashGetAllAsync(Key) : Database.HashGetAllAsync(Key);

        try
        {
            await t;
            _entries = t.Result.ToDictionary(
                x => x.Name, x => new KeyValuePair<byte[], bool>(x.Value, false));
        }
        catch
        {
        }
    }

    public void Reload(string field = null)
    {
        if (field != null && _entries != null)
        {
            _entries[field] = new KeyValuePair<byte[], bool>(
                Database.HashGet(Key, field), false);
            return;
        }

        _entries = Database.HashGetAll(Key)
            .ToDictionary(
                x => x.Name,
                x => new KeyValuePair<byte[], bool>(x.Value, false));
    }
}

public class DbLoginInfo
{
    private IDatabase db;

    internal DbLoginInfo(IDatabase db, string uuid)
    {
        this.db = db;
        UUID = uuid;
        var json = (string)db.HashGet("logins", uuid.ToUpperInvariant());
        if (json == null)
            IsNull = true;
        else
            JsonConvert.PopulateObject(json, this);
    }

    [JsonIgnore] public string UUID { get; private set; }

    [JsonIgnore] public bool IsNull { get; private set; }

    public string Salt { get; set; }
    public string HashedPassword { get; set; }
    public int AccountId { get; set; }

    public void Flush()
    {
        db.HashSet("logins", UUID.ToUpperInvariant(), JsonConvert.SerializeObject(this));
    }
}

public class DbAccount : RedisObject
{
    public DbAccount(IDatabase db, int accId, string field = null)
    {
        AccountId = accId;
        Init(db, "account." + accId, field);

        if (field != null)
            return;

        var time = Utils.FromUnixTimestamp(BanLiftTime);
        if (!Banned || BanLiftTime <= -1 || time > DateTime.UtcNow) return;
        Banned = false;
        BanLiftTime = 0;
        FlushAsync();
    }

    public int AccountId { get; private set; }

    public int AccountIdOverride
    {
        get => GetValue<int>("accountIdOverride");
        set => SetValue("accountIdOverride", value);
    }

    public int AccountIdOverrider { get; set; }

    internal string LockToken { get; set; }

    public string UUID
    {
        get => GetValue<string>("uuid");
        set => SetValue("uuid", value);
    }

    public string Name
    {
        get => GetValue<string>("name");
        set => SetValue("name", value);
    }

    public bool Admin
    {
        get => GetValue<bool>("admin");
        set => SetValue("admin", value);
    }

    public int GuildId
    {
        get => GetValue<int>("guildId");
        set => SetValue("guildId", value);
    }

    public int GuildRank
    {
        get => GetValue<int>("guildRank");
        set => SetValue("guildRank", value);
    }

    public int GuildFame
    {
        get => GetValue<int>("guildFame");
        set => SetValue("guildFame", value);
    }

    public int VaultCount
    {
        get => GetValue<int>("vaultCount");
        init => SetValue("vaultCount", value);
    }

    public int NextGiftId
    {
        get => GetValue<int>("nextGiftId");
        set => SetValue("nextGiftId", value);
    }

    public HashSet<int> ActiveGiftChests
    {
        get => GetValue("activeGiftChests", new HashSet<int>());
        set => SetValue("activeGiftChests", value);
    }

    // Market
    public int[] MarketOffers
    {
        get => GetValue<int[]>("marketOffers") ?? new int[0];
        set => SetValue("marketOffers", value);
    }

    public int MaxCharSlot
    {
        get => GetValue<int>("maxCharSlot");
        set => SetValue("maxCharSlot", value);
    }

    public DateTime RegTime
    {
        get => GetValue<DateTime>("regTime");
        set => SetValue("regTime", value);
    }

    public int Credits
    {
        get => GetValue<int>("credits");
        set => SetValue("credits", value);
    }

    public int TotalCredits
    {
        get => GetValue<int>("totalCredits");
        set => SetValue("totalCredits", value);
    }

    public int NextCharId
    {
        get => GetValue<int>("nextCharId");
        set => SetValue("nextCharId", value);
    }

    public int LegacyRank
    {
        get => GetValue<int>("rank");
        set => SetValue("rank", value);
    }

    public ushort[] Skins
    {
        get => GetValue<ushort[]>("skins") ?? new ushort[0];
        set => SetValue("skins", value);
    }

    public int[] LockList
    {
        get => GetValue<int[]>("lockList") ?? new int[0];
        set => SetValue("lockList", value);
    }

    public int[] IgnoreList
    {
        get => GetValue<int[]>("ignoreList") ?? new int[0];
        set => SetValue("ignoreList", value);
    }

    public bool Banned
    {
        get => GetValue<bool>("banned");
        set => SetValue("banned", value);
    }

    public string Notes
    {
        get => GetValue<string>("notes");
        init => SetValue("notes", value);
    }

    public bool Hidden
    {
        get => GetValue<bool>("hidden");
        set => SetValue("hidden", value);
    }

    public int GlowColor
    {
        get => GetValue<int>("glow");
        set => SetValue("glow", value);
    }

    public string PassResetToken
    {
        get => GetValue<string>("passResetToken");
        set => SetValue("passResetToken", value);
    }

    public string IP
    {
        get => GetValue<string>("ip");
        set => SetValue("ip", value);
    }

    public int BanLiftTime
    {
        get => GetValue<int>("banLiftTime");
        init => SetValue("banLiftTime", value);
    }

    public List<string> Emotes
    {
        get => GetValue<string>("emotes")?.CommaToArray<string>()?.ToList() ?? new List<string>();
        set => SetValue("emotes", value?.ToArray().ToCommaSepString() ?? string.Empty);
    }

    public int LastSeen
    {
        get => GetValue<int>("lastSeen");
        set => SetValue("lastSeen", value);
    }

    public int Size
    {
        get => GetValue<int>("size");
        set => SetValue("size", value);
    }

    public int Rank => LegacyRank;

    public void RefreshLastSeen()
    {
        LastSeen = (int)DateTime.UtcNow.Subtract(new DateTime(1970, 1, 1)).TotalSeconds;
    }
}

public class DbChar : RedisObject
{
    public DbAccount Account { get; private set; }
    public int CharId { get; private set; }

    public DbChar(DbAccount acc, int charId)
    {
        Account = acc;
        CharId = charId;
        Init(acc.Database, "char." + acc.AccountId + "." + charId);
    }

    public ushort ObjectType
    {
        get => GetValue<ushort>("charType");
        init => SetValue("charType", value);
    }

    public ushort[] Items
    {
        get => GetValue<ushort[]>("items");
        set => SetValue("items", value);
    }

    public int HP
    {
        get => GetValue<int>("hp");
        set => SetValue("hp", value);
    }

    public int MP
    {
        get => GetValue<int>("mp");
        set => SetValue("mp", value);
    }

    public int[] Stats
    {
        get => GetValue<int[]>("stats");
        set => SetValue("stats", value);
    }

    public int Tex1
    {
        get => GetValue<int>("tex1");
        set => SetValue("tex1", value);
    }

    public int Tex2
    {
        get => GetValue<int>("tex2");
        set => SetValue("tex2", value);
    }

    public int Skin
    {
        get => GetValue<int>("skin");
        set => SetValue("skin", value);
    }
        
    public DateTime CreateTime
    {
        get => GetValue<DateTime>("createTime");
        set => SetValue("createTime", value);
    }

    public DateTime LastSeen
    {
        get => GetValue<DateTime>("lastSeen");
        set => SetValue("lastSeen", value);
    }

    public bool Dead
    {
        get => GetValue<bool>("dead");
        set => SetValue("dead", value);
    }

    public int Tier {
        get => GetValue<int>("tier");
        set => SetValue("tier", value);
    }
}

public class DbDeath : RedisObject
{
    public DbAccount Account { get; private set; }
    public int CharId { get; private set; }

    public DbDeath(DbAccount acc, int charId)
    {
        Account = acc;
        CharId = charId;
        Init(acc.Database, "death." + acc.AccountId + "." + charId);
    }

    public ushort ObjectType
    {
        get => GetValue<ushort>("objType");
        init => SetValue("objType", value);
    }

    public string Killer
    {
        get => GetValue<string>("killer");
        init => SetValue("killer", value);
    }

    public bool FirstBorn
    {
        get => GetValue<bool>("firstBorn");
        init => SetValue("firstBorn", value);
    }

    public DateTime DeathTime
    {
        get => GetValue<DateTime>("deathTime");
        init => SetValue("deathTime", value);
    }
}

public struct DbNewsEntry
{
    [JsonIgnore] public DateTime Date;
    public string Icon;
    public string Title;
    public string Text;
    public string Link;
}

public class DbNews // TODO. Check later, range results might be bugged...
{
    public DbNews(IDatabase db, int count)
    {
        news = db.SortedSetRangeByRankWithScores("news", 0, count)
            .Select(x =>
            {
                var ret = JsonConvert.DeserializeObject<DbNewsEntry>(
                    Encoding.UTF8.GetString(x.Element));
                ret.Date = new DateTime(1970, 1, 1, 0, 0, 0).AddSeconds(x.Score);
                return ret;
            }).ToArray();
    }

    private DbNewsEntry[] news;

    public DbNewsEntry[] Entries => news;
}

public abstract class RInventory : RedisObject
{
    public string Field { get; protected init; }

    public ushort[] Items
    {
        get => GetValue<ushort[]>(Field) ?? Enumerable.Repeat(ushort.MaxValue, 22).ToArray();
        set => SetValue(Field, value);
    }
}

public class DbVaultSingle : RInventory
{
    public DbVaultSingle(DbAccount acc, int vaultIndex)
    {
        Field = "vault." + vaultIndex;
        Init(acc.Database, "vault." + acc.AccountId, Field);

        var items = GetValue<ushort[]>(Field);
        if (items != null)
            return;

        var trans = Database.CreateTransaction();
        SetValue<ushort[]>(Field, Items);
        FlushAsync(trans);
        trans.Execute(CommandFlags.FireAndForget);
    }
}

public class DbCharInv : RInventory
{
    public DbCharInv(DbAccount acc, int charId)
    {
        Field = "items";
        Init(acc.Database, "char." + acc.AccountId + "." + charId, Field);
    }
}

public class DbGuild : RedisObject
{
    internal readonly object MemberLock; // maybe use redis locking?

    internal DbGuild(IDatabase db, int id)
    {
        MemberLock = new object();

        Id = id;
        Init(db, "guild." + id);
    }

    public DbGuild(DbAccount acc)
    {
        MemberLock = new object();

        Id = acc.GuildId;
        Init(acc.Database, "guild." + Id);
    }

    public int Id { get; private set; }

    public string Name
    {
        get => GetValue<string>("name");
        init => SetValue("name", value);
    }

    public int Level
    {
        get => GetValue<int>("level");
        set => SetValue("level", value);
    }

    public int[] Members // list of member account id's
    {
        get => GetValue<int[]>("members") ?? new int[0];
        set => SetValue("members", value);
    }

    public string Board
    {
        get => GetValue<string>("board") ?? "";
        set => SetValue("board", value);
    }
}

public class DbIpInfo
{
    private readonly IDatabase _db;

    internal DbIpInfo(IDatabase db, string ip)
    {
        _db = db;
        IP = ip;
        var json = (string)db.HashGet("ips", ip);
        if (json == null)
            IsNull = true;
        else
            JsonConvert.PopulateObject(json, this);
    }

    [JsonIgnore] public string IP { get; private set; }

    [JsonIgnore] public bool IsNull { get; private set; }

    public HashSet<int> Accounts { get; set; }
    public bool Banned { get; set; }
    public string Notes { get; set; }

    public void Flush()
    {
        _db.HashSetAsync("ips", IP, JsonConvert.SerializeObject(this));
    }
}

public class AccountMail
{
    [JsonProperty("id", DefaultValueHandling = DefaultValueHandling.Include)]
    public int Id;

    [JsonProperty("add", DefaultValueHandling = DefaultValueHandling.Include)]
    public int AddTime;

    [JsonProperty("ends", DefaultValueHandling = DefaultValueHandling.Include)]
    public int EndTime;

    [JsonProperty("charId", DefaultValueHandling = DefaultValueHandling.Include)]
    public int CharacterId;

    [JsonProperty("priority")] public int Priority;
    [JsonProperty("content")] public string Content;

    public static AccountMail Read(NReader rdr)
    {
        var ret = new AccountMail();
        ret.Id = rdr.ReadInt32();
        ret.AddTime = rdr.ReadInt32();
        ret.EndTime = rdr.ReadInt32();
        ret.CharacterId = rdr.ReadInt32();
        ret.Priority = rdr.ReadInt32();
        ret.Content = rdr.ReadUTF();
        return ret;
    }

    public void Write(NWriter wtr)
    {
        wtr.Write(Id);
        wtr.Write(AddTime);
        wtr.Write(EndTime);
        wtr.Write(CharacterId);
        wtr.Write(Priority);
        wtr.WriteUTF(Content);
    }
}