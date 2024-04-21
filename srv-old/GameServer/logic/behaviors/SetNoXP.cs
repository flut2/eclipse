using System.Xml.Linq;
using GameServer.realm;

namespace GameServer.logic.behaviors; 

internal class SetNoXp : Behavior
{
    //State storage: nothing
        
    public SetNoXp(XElement e)
    {
    }
        
    public SetNoXp()
    {
    }

    protected override void OnStateEntry(Entity host, RealmTime time, ref object state)
    {
        host.GivesNoXp = true;
    }

    protected override void TickCore(Entity host, RealmTime time, ref object state)
    {
    }
}