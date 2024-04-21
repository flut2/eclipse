using System.Xml.Linq;
using Shared;
using GameServer.realm;
using GameServer.realm.entities;
using GameServer.realm.entities.player;

namespace GameServer.logic.behaviors; 

internal class Taunt : Behavior
{
    //State storage: time

    private float probability = 1;
    private bool broadcast = false;
    private Cooldown cooldown;
    private string[] text;
    private int? ordered;
    
    public Taunt(XElement e)
    {
        text = e.ParseStringArray("@text", '|', new[] { e.ParseString("@text") });
        probability = e.ParseFloat("@probability", 1);
        broadcast = e.ParseBool("@broadcast");
        cooldown = new Cooldown(e.ParseLong("@cooldown") * 1000, 0);
    }

    protected override void OnStateEntry(Entity host, RealmTime time, ref object state)
    {
        state = null;
    }

    protected override void TickCore(Entity host, RealmTime time, ref object state) {
        if (state != null && cooldown.CoolDown == 0) return; //cooldown = 0 -> once per state entry

        long c;
        if (state == null) c = cooldown.Next(Random);
        else c = (long) state;

        c -= time.ElapsedUsDelta;
        state = c;
        if (c > 0) return;

        c = cooldown.Next(Random);
        state = c;

        if (Random.NextDouble() >= probability) return;

        string taunt;
        if (ordered != null) {
            taunt = text[ordered.Value];
            ordered = (ordered.Value + 1) % text.Length;
        }
        else
            taunt = text[Random.Next(text.Length)];

        if (taunt.Contains("{PLAYER}")) {
            var player = host.GetNearestEntity(10, null);
            if (player == null) return;
            taunt = taunt.Replace("{PLAYER}", player.Name);
        }

        taunt = taunt.Replace("{HP}", (host as Enemy)?.HP.ToString());

        if (broadcast) {
            foreach (var p in host.Owner.Players.Values)
                if (p != host)
                    p.Client.SendText(host.ObjectDesc.DisplayId ?? host.ObjectDesc.ObjectId, host.Id, 3, "",
                        taunt, 0xF2963A, 0xF2963A);
        } else
            foreach (var i in host.Owner.PlayersCollision.HitTest(host.X, host.Y, 15).Where(e => e is Player))
                if (i is Player player && host.Dist(player) < 15)
                    player.Client.SendText(host.ObjectDesc.DisplayId ?? host.ObjectDesc.ObjectId, host.Id, 3, "",
                        taunt, 0xF2963A, 0xF2963A);
    }
}