using System.Collections.ObjectModel;
using System.Xml.Linq;
using Shared;

namespace LoginServer;

internal class ServerItem
{
    public string Name { get; init; }
    public string DNS { get; init; }
    public int Port { get; init; }
    public double Lat { get; init; }
    public double Long { get; init; }
    public int Usage { get; init; }
    public int MaxPlayers { get; set; }
    public bool AdminOnly { get; init; }

    public XElement ToXml()
    {
        return
            new XElement("Server",
                new XElement("Name", Name),
                new XElement("DNS", DNS),
                new XElement("Port", Port),
                new XElement("Lat", Lat),
                new XElement("Long", Long),
                new XElement("Usage", Usage),
                new XElement("MaxPlayers", MaxPlayers),
                new XElement("AdminOnly", AdminOnly)
            );
    }
}

internal class NewsItem
{
    public string Icon { get; internal init; }
    public string Title { get; internal init; }
    public string TagLine { get; internal init; }
    public string Link { get; internal init; }
    public DateTime Date { get; internal init; }

    public static NewsItem FromDb(DbNewsEntry entry)
    {
        return new NewsItem()
        {
            Icon = entry.Icon,
            Title = entry.Title,
            TagLine = entry.Text,
            Link = entry.Link,
            Date = entry.Date
        };
    }

    public XElement ToXml()
    {
        return
            new XElement("Item",
                new XElement("Icon", Icon),
                new XElement("Title", Title),
                new XElement("TagLine", TagLine),
                new XElement("Link", Link),
                new XElement("Date", Date.ToUnixTimestamp())
            );
    }
}

internal class GuildMember
{
    private string _name;
    private int _rank;
    private int _guildFame;
    private Int32 _lastSeen;

    public static GuildMember FromDb(DbAccount acc)
    {
        return new GuildMember()
        {
            _name = acc.Name,
            _rank = acc.GuildRank,
            _guildFame = acc.GuildFame,
            _lastSeen = acc.LastSeen
        };
    }

    public XElement ToXml()
    {
        return new XElement("Member",
            new XElement("Name", _name),
            new XElement("Rank", _rank),
            new XElement("Fame", _guildFame),
            new XElement("LastSeen", _lastSeen));
    }
}

internal class Guild
{
    private int _id;
    private string _name;
    private int _level;
    private string _hallType;
    private List<GuildMember> _members;

    public static Guild FromDb(Database db, DbGuild guild)
    {
        var members = (from member in guild.Members
            select db.GetAccount(member)
            into acc
            where acc != null
            orderby acc.GuildRank descending,
                acc.GuildFame descending,
                acc.Name ascending
            select GuildMember.FromDb(acc)).ToList();

        return new Guild()
        {
            _id = guild.Id,
            _name = guild.Name,
            _level = guild.Level,
            _hallType = "Guild Hall " + guild.Level,
            _members = members
        };
    }

    public XElement ToXml()
    {
        var guild = new XElement("Guild");
        guild.Add(new XAttribute("id", _id));
        guild.Add(new XAttribute("name", _name));
        guild.Add(new XAttribute("level", _level));
        guild.Add(new XElement("HallType", _hallType));
        foreach (var member in _members)
            guild.Add(member.ToXml());

        return guild;
    }
}

internal class GuildIdentity
{
    private int _id;
    private string _name;
    private int _rank;

    public static GuildIdentity FromDb(DbAccount acc, DbGuild guild)
    {
        return new GuildIdentity()
        {
            _id = guild.Id,
            _name = guild.Name,
            _rank = acc.GuildRank
        };
    }

    public XElement ToXml()
    {
        return
            new XElement("Guild",
                new XAttribute("id", _id),
                new XElement("Name", _name),
                new XElement("Rank", _rank)
            );
    }
}

internal class Account
{
    public int AccountId { get; private init; }
    public string Name { get; init; }
        
    public bool Admin { get; private init; }
    public int Rank { get; private init; }

    public int Credits { get; private init; }
    public int NextCharSlotPrice { get; private init; }
    public int CharSlotCurrency { get; private init; }
    public string MenuMusic { get; private init; }
    public string DeadMusic { get; private init; }
    public int MapMinRank { get; private init; }
    public int SpriteMinRank { get; private init; }

    public GuildIdentity Guild { get; private init; }

    public ushort[] Skins { get; private init; }

    public bool Banned { get; private init; }
    public string BanReasons { get; private init; }
    public int BanLiftTime { get; private init; }
    public int LastSeen { get; private init; }

    public static Account FromDb(DbAccount acc)
    {
        return new Account
        {
            AccountId = acc.AccountId,
            Name = acc.Name,

            Admin = acc.Admin,
            Rank = acc.Rank,
                
            Credits = acc.Credits,
            NextCharSlotPrice = Program.Resources.Settings.CharacterSlotCost,
            CharSlotCurrency = Program.Resources.Settings.CharacterSlotCurrency,
            MenuMusic = Program.Resources.Settings.MenuMusic,
            DeadMusic = Program.Resources.Settings.DeadMusic,
            MapMinRank = Program.Resources.Settings.MapMinRank,
            SpriteMinRank = Program.Resources.Settings.SpriteMinRank,

            Guild = GuildIdentity.FromDb(acc, new DbGuild(acc)),

            Skins = acc.Skins ?? Array.Empty<ushort>(),
            Banned = acc.Banned,
            BanReasons = acc.Notes,
            BanLiftTime = acc.BanLiftTime,
            LastSeen = acc.LastSeen
        };
    }

    public XElement ToXml()
    {
        return
            new XElement("Account",
                new XElement("AccountId", AccountId),
                new XElement("Name", Name),
                Admin ? new XElement("Admin", "") : null,
                new XElement("Rank", Rank),
                new XElement("LastSeen", LastSeen),
                Banned ? new XElement("Banned", BanReasons).AddAttribute("liftTime", BanLiftTime) : null,
                new XElement("Credits", Credits),
                new XElement("NextCharSlotPrice", NextCharSlotPrice),
                new XElement("CharSlotCurrency", CharSlotCurrency),
                new XElement("MenuMusic", MenuMusic),
                new XElement("DeadMusic", DeadMusic),
                new XElement("MapMinRank", MapMinRank),
                new XElement("SpriteMinRank", SpriteMinRank),
                Guild.ToXml()
            );
    }
}

internal class Character
{
    public int CharacterId { get; private init; }
    public ushort ObjectType { get; private init; }
    public ushort[] Equipment { get; private init; }
    public int Health { get; private init; }
    public int Mana { get; private init; }
    public int Strength { get; private init; }
    public int Wit { get; private init; }
    public int Defense { get; private init; }
    public int Resistance { get; private init; }
    public int Speed { get; private init; }
    public int Haste { get; private init; }
    public int Stamina { get; private init; }
    public int Intelligence { get; private init; }
    public int Piercing { get; private init; }
    public int Penetration { get; private init; }
    public int Tenacity { get; private init; }
    public int Tex1 { get; private init; }
    public int Tex2 { get; private init; }
    public int Skin { get; private init; }
    public bool Dead { get; private init; }

    public static Character FromDb(DbChar character, bool dead)
    {
        return new Character()
        {
            CharacterId = character.CharId,
            ObjectType = character.ObjectType,
            Equipment = character.Items,
            Health = character.Stats[0],
            Mana = character.Stats[1],
            Strength = character.Stats[2],
            Wit = character.Stats[3],
            Defense = character.Stats[4],
            Resistance = character.Stats[5],
            Speed = character.Stats[6],
            Stamina = character.Stats[7],
            Intelligence = character.Stats[8],
            Penetration = character.Stats[9],
            Piercing = character.Stats[10],
            Haste = character.Stats[11],
            Tenacity = character.Stats[12],
            Tex1 = character.Tex1,
            Tex2 = character.Tex2,
            Skin = character.Skin,
            Dead = dead
        };
    }

    public XElement ToXml()
    {
        return
            new XElement("Char",
                new XAttribute("id", CharacterId),
                new XElement("ObjectType", ObjectType),
                new XElement("Health", Health),
                new XElement("Mana", Mana),
                new XElement("Strength", Strength),
                new XElement("Wit", Wit),
                new XElement("Defense", Defense),
                new XElement("Resistance", Resistance),
                new XElement("Speed", Speed),
                new XElement("Haste", Haste),
                new XElement("Stamina", Stamina),
                new XElement("Intelligence", Intelligence),
                new XElement("Piercing", Piercing),
                new XElement("Penetration", Penetration),
                new XElement("Tenacity", Tenacity),
                new XElement("Tex1", Tex1),
                new XElement("Tex2", Tex2),
                new XElement("Texture", Skin),
                new XElement("Dead", Dead),
                new XElement("Equipment", Equipment.ToCommaSepString())
            );
    }
}

internal class ItemCosts
{
    private static readonly XElement ItemCostsXml;

    static ItemCosts()
    {
        var elem = new XElement("ItemCosts");
        foreach (var skin in Program.Resources.GameData.Skins.Values)
        {
            var ca = new XElement("ItemCost", skin.Cost);
            ca.Add(new XAttribute("type", skin.Type));
            ca.Add(new XAttribute("expires", (skin.Expires) ? "1" : "0"));
            ca.Add(new XAttribute("purchasable", (!skin.Restricted) ? "1" : "0"));

            elem.Add(ca);
        }

        ItemCostsXml = elem;
    }

    public static XElement ToXml()
    {
        return ItemCostsXml;
    }
}

internal class CharList
{
    public Character[] Characters { get; private init; }
    public int NextCharId { get; private init; }
    public int MaxNumChars { get; private init; }

    public Account Account { get; private init; }

    public IEnumerable<NewsItem> News { get; private init; }
    public List<ServerItem> Servers { get; set; }
    
    public double? Lat { get; set; }
    public double? Long { get; set; }

    private static IEnumerable<NewsItem> GetItems(Database db, DbAccount acc)
    {
        var news = new DbNews(db.Conn, 10).Entries
            .Select(x => NewsItem.FromDb(x)).ToArray();
        var chars = db.GetDeadCharacters(acc).Take(10).Select(x =>
        {
            var death = new DbDeath(acc, x);
            return new NewsItem()
            {
                Icon = "fame",
                Title = "Your " + Program.Resources.GameData.ObjectTypeToId[death.ObjectType]
                                + " died at level " + 0,
                TagLine = "",
                Link = "fame:" + death.CharId,
                Date = death.DeathTime
            };
        });
        return news.Concat(chars).OrderByDescending(x => x.Date);
    }

    public static CharList FromDb(Database db, DbAccount acc)
    {
        return new CharList()
        {
            Characters = db.GetAliveCharacters(acc)
                .Select(x => Character.FromDb(db.LoadCharacter(acc, x), false))
                .ToArray(),
            NextCharId = acc.NextCharId,
            MaxNumChars = acc.MaxCharSlot,
            Account = Account.FromDb(acc),
            News = GetItems(db, acc),
        };
    }

    public XElement ToXml()
    {
        return
            new XElement("Chars",
                new XAttribute("nextCharId", NextCharId),
                new XAttribute("maxNumChars", MaxNumChars),
                Characters.Select(x => x.ToXml()),
                Account.ToXml(),
                new XElement("News",
                    News.Select(x => x.ToXml())
                ),
                new XElement("Servers",
                    Servers.Select(x => x.ToXml())
                ),
                Lat == null ? null : new XElement("Lat", Lat),
                Long == null ? null : new XElement("Long", Long),
                (Account.Skins.Length > 0) ? new XElement("OwnedSkins", Account.Skins.ToCommaSepString()) : null,
                ItemCosts.ToXml()
            );
    }
}

internal class FameListEntry
{
    public int AccountId { get; private init; }
    public int CharId { get; private init; }
    public string Name { get; private init; }
    public ushort ObjectType { get; private init; }
    public int Tex1 { get; private init; }
    public int Tex2 { get; private init; }
    public int Skin { get; private init; }

    public static FameListEntry FromDb(DbChar character)
    {
        var death = new DbDeath(character.Account, character.CharId);
        return new FameListEntry()
        {
            AccountId = character.Account.AccountId,
            CharId = character.CharId,
            Name = character.Account.Name,
            ObjectType = character.ObjectType,
            Tex1 = character.Tex1,
            Tex2 = character.Tex2,
            Skin = character.Skin,
        };
    }

    public XElement ToXml()
    {
        return
            new XElement("FameListElem",
                new XAttribute("accountId", AccountId),
                new XAttribute("charId", CharId),
                new XElement("Name", Name),
                new XElement("ObjectType", ObjectType),
                new XElement("Tex1", Tex1),
                new XElement("Tex2", Tex2),
                new XElement("Texture", Skin)
            );
    }
}