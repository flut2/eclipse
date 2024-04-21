using System.Text;
using System.Xml.Linq;
using Shared;
using GameServer.realm;
using GameServer.realm.worlds.logic;

namespace GameServer.logic.behaviors; 

internal class SayInWorld : Behavior
{
    public static readonly string PLAYER_COUNT = "{COUNT}";
    public static readonly string PLAYER_LIST = "{PL_LIST}";
    private readonly string _message;
    private readonly string _name;

    public SayInWorld(XElement e)
    {
        _name = e.ParseString("@name");
        _message = e.ParseString("@message");
    }

    public SayInWorld(string name, string msg)
    {
        _name = name;
        _message = msg;
    }

    protected override void OnStateEntry(Entity host, RealmTime time, ref object state)
    {
        var owner = host.Owner;
        var players = owner.Players.Values
            .Where(p => p.Client != null && p.Admin == 0)
            .ToArray();

        var sb = new StringBuilder();
        for (var i = 0; i < players.Length; i++)
        {
            if (i != 0)
                sb.Append(", ");
            sb.Append(players[i].Name);
        }

        var playerList = sb.ToString();
        var playerCount = owner.Players.Values.Count(p => p.Client != null && p.Admin == 0).ToString();

        var msg = _message.Replace(PLAYER_COUNT, playerCount).Replace(PLAYER_LIST, playerList);

        host.Manager.Chat.Enemy(host.Owner, _name, msg);
    }

    protected override void TickCore(Entity host, RealmTime time, ref object state)
    {
    }
}