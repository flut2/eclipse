using Shared;
using GameServer.realm.entities.player;
using GameServer.realm.worlds;
using NLog;

namespace GameServer.realm; 

public class ChatManager : IDisposable
{
    private static readonly string[] exclusiveEmotes =
        { ":whitebag:", ":bluebag:", ":cyanbag:", ":rip:", ":pbag:" };

    private static Logger Log = LogManager.GetCurrentClassLogger();

    private RealmManager manager;

    public ChatManager(RealmManager manager)
    {
        this.manager = manager;
        manager.InterServer.AddHandler<ChatMsg>(Channel.Chat, HandleChat);
        manager.InterServer.NewServer += AnnounceNewServer;
        manager.InterServer.ServerQuit += AnnounceServerQuit;
    }

    private void AnnounceNewServer(object sender, EventArgs e)
    {
        var networkMsg = (InterServerEventArgs<NetworkMsg>)e;
        if (networkMsg.Content.Info.type == ServerType.Account)
            return;
        Announce($"A new server has come online: {networkMsg.Content.Info.name}", true);
    }

    private void AnnounceServerQuit(object sender, EventArgs e)
    {
        var networkMsg = (InterServerEventArgs<NetworkMsg>)e;
        if (networkMsg.Content.Info.type == ServerType.Account)
            return;
        Announce($"Server, {networkMsg.Content.Info.name}, is no longer online.", true);
    }

    public void Dispose()
    {
        manager.InterServer.NewServer -= AnnounceNewServer;
        manager.InterServer.ServerQuit -= AnnounceServerQuit;
    }

    public void Say(Player src, string text)
    {
        foreach (var word in text.Split(' ')
                     .Where(word => word.StartsWith(":") && word.EndsWith(":") && exclusiveEmotes.Contains(word))
                     .Where(word => !src.Client.Account.Emotes.Contains(word)))
            text = text.Replace(word, string.Empty);

        if (string.IsNullOrWhiteSpace(text))
            return;

        foreach (var plr in src.Owner.Players.Values)
            plr.Client.SendText(src.Name, src.Id, 5, "", text,
                (uint) (src.Admin != 0 ? 0xF2CA46 : 0xEBEBEB), (uint)(src.Admin != 0 ? 0xD4AF37 : 0xB0B0B0));
    }

    public void Announce(string text, bool local = false)
    {
        if (string.IsNullOrWhiteSpace(text))
            return;

        if (local)
        {
            foreach (var i in manager.Clients.Keys
                         .Where(x => x.Player != null)
                         .Select(x => x.Player))
            {
                i.AnnouncementReceived(text);
            }

            return;
        }

        manager.InterServer.Publish(Channel.Chat, new ChatMsg()
        {
            Type = ChatType.Announce,
            Inst = manager.InstanceId,
            Text = text
        });
    }

    public bool SendInfo(int target, string text)
    {
        if (String.IsNullOrWhiteSpace(text))
            return true;

        manager.InterServer.Publish(Channel.Chat, new ChatMsg()
        {
            Type = ChatType.Info,
            Inst = manager.InstanceId,
            To = target,
            Text = text
        });
        return true;
    }
        
    public void Enemy(World world, string name, string text)
    {
        if (string.IsNullOrWhiteSpace(text))
            return;

        foreach (var p in world.Players.Values)
            p.Client.SendText(name, 0, 0, "", text);
        Log.Info("[{0}({1})] <{3}> {2}", world.Name, world.Id, text, name);
    }

    public bool Tell(Player src, string target, string text)
    {
        foreach (var word in text.Split(' ')
                     .Where(word => word.StartsWith(":") && word.EndsWith(":") && exclusiveEmotes.Contains(word))
                     .Where(word => !src.Client.Account.Emotes.Contains(word)))
            text = text.Replace(word, string.Empty);

        if (String.IsNullOrWhiteSpace(text))
            return true;

        var id = manager.Database.ResolveId(target);
        if (id == 0) return false;

        if (!manager.Database.AccountLockExists(id))
            return false;

        var acc = manager.Database.GetAccount(id);
        if (acc == null || acc.Hidden && src.Admin == 0)
            return false;

        manager.InterServer.Publish(Channel.Chat, new ChatMsg()
        {
            Type = ChatType.Tell,
            Inst = manager.InstanceId,
            ObjId = src.Id,
            Admin = src.Admin,
            From = src.Client.Account.AccountId,
            To = id,
            Text = text,
            SrcIP = src.Client.IP
        });
        return true;
    }

    public bool Invite(Player src, string target, string dungeon, int wid)
    {
        var id = manager.Database.ResolveId(target);
        if (id == 0) return false;

        if (!manager.Database.AccountLockExists(id))
            return false;

        var acc = manager.Database.GetAccount(id);
        if (acc == null || acc.Hidden && src.Admin == 0)
            return false;

        manager.InterServer.Publish(Channel.Chat, new ChatMsg()
        {
            Type = ChatType.Invite,
            Inst = manager.InstanceId,
            ObjId = wid,
            From = src.Client.Account.AccountId,
            To = id,
            Text = dungeon
        });
        return true;
    }

    public bool Guild(Player src, string text, bool announce = false)
    {
        foreach (var word in text.Split(' ')
                     .Where(word => word.StartsWith(":") && word.EndsWith(":") && exclusiveEmotes.Contains(word))
                     .Where(word => !src.Client.Account.Emotes.Contains(word)))
            text = text.Replace(word, String.Empty);

        if (String.IsNullOrWhiteSpace(text))
            return true;

        manager.InterServer.Publish(Channel.Chat, new ChatMsg()
        {
            Type = (announce) ? ChatType.GuildAnnounce : ChatType.Guild,
            Inst = manager.InstanceId,
            ObjId = src.Id,
            Admin = src.Admin,
            From = src.Client.Account.AccountId,
            To = src.Client.Account.GuildId,
            Text = text
        });
        return true;
    }

    public bool GuildAnnounce(DbAccount acc, string text)
    {
        if (String.IsNullOrWhiteSpace(text))
            return true;

        manager.InterServer.Publish(Channel.Chat, new ChatMsg()
        {
            Type = ChatType.GuildAnnounce,
            Inst = manager.InstanceId,
            From = acc.AccountId,
            To = acc.GuildId,
            Text = text,
            Hidden = acc.Hidden
        });
        return true;
    }

    private void HandleChat(object sender, InterServerEventArgs<ChatMsg> e)
    {
        switch (e.Content.Type)
        {
            case ChatType.Invite:
            {
                var from = manager.Database.ResolveIgn(e.Content.From);
                foreach (var i in manager.Clients.Keys
                             .Where(x => x.Player != null)
                             .Where(x => !x.Account.IgnoreList.Contains(e.Content.From))
                             .Where(x => x.Account.AccountId == e.Content.To)
                             .Select(x => x.Player))
                {
                    //i.Invited(e.Content.ObjId, from, e.Content.Text);
                }
            }
                break;
            case ChatType.Tell:
            {
                var from = manager.Database.ResolveIgn(e.Content.From);
                var to = manager.Database.ResolveIgn(e.Content.To);
                foreach (var i in manager.Clients.Keys
                             .Where(x => x.Player != null)
                             .Where(x => !x.Account.IgnoreList.Contains(e.Content.From))
                             .Where(x => x.Account.AccountId == e.Content.From ||
                                         x.Account.AccountId == e.Content.To &&
                                         (x.Account.IP == e.Content.SrcIP))
                             .Select(x => x.Player))
                {
                    i.TellReceived(
                        e.Content.Inst == manager.InstanceId ? e.Content.ObjId : -1,
                        e.Content.Stars, e.Content.Admin, from, to, e.Content.Text);
                }
            }
                break;
            case ChatType.Guild:
            {
                var from = manager.Database.ResolveIgn(e.Content.From);
                foreach (var i in manager.Clients.Keys
                             .Where(x => x.Player != null)
                             .Where(x => !x.Account.IgnoreList.Contains(e.Content.From))
                             .Where(x => x.Account.GuildId > 0)
                             .Where(x => x.Account.GuildId == e.Content.To)
                             .Select(x => x.Player))
                {
                    i.GuildReceived(
                        e.Content.Inst == manager.InstanceId ? e.Content.ObjId : -1,
                        e.Content.Stars, e.Content.Admin, from, e.Content.Text);
                }
            }
                break;
            case ChatType.GuildAnnounce:
            {
                foreach (var i in manager.Clients.Keys
                             .Where(x => x.Player != null)
                             .Where(x => x.Account.GuildId > 0)
                             .Where(x => x.Account.GuildId == e.Content.To)
                             .Where(x => !e.Content.Hidden || x.Account.Admin)
                             .Select(x => x.Player))
                {
                    i.GuildReceived(-1, -1, 0, "", e.Content.Text);
                }
            }
                break;
            case ChatType.Announce:
            {
                foreach (var i in manager.Clients.Keys
                             .Where(x => x.Player != null)
                             .Select(x => x.Player))
                {
                    i.AnnouncementReceived(e.Content.Text);
                }
            }
                break;
            case ChatType.Info:
            {
                var player = manager.Clients.Keys.Where(c => c.Account.AccountId == e.Content.To).FirstOrDefault();
                player?.Player.SendInfo(e.Content.Text);
            }
                break;
        }
    }
}