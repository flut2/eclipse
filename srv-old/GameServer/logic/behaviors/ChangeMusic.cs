using System.Xml.Linq;
using Shared;
using GameServer.realm;

namespace GameServer.logic.behaviors; 

internal class ChangeMusic : Behavior
{
    //State storage: none

    private readonly string _music;

    public ChangeMusic(XElement e)
    {
        _music = e.ParseString("@song");
    }
        
    public ChangeMusic(string song)
    {
        _music = song;
    }

    protected override void TickCore(Entity host, RealmTime time, ref object state)
    {
    }

    protected override void OnStateEntry(Entity host, RealmTime time, ref object state)
    {
        if (host.Owner.Music != _music)
        {
            var owner = host.Owner;

            owner.Music = _music;

            var i = 0;
        }
    }
}