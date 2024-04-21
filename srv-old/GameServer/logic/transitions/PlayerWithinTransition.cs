using System.Xml.Linq;
using Shared;
using GameServer.realm;
using GameServer.realm.entities.player;

namespace GameServer.logic.transitions; 

internal class PlayerWithinTransition : Transition
{
    //State storage: none

    private readonly double _dist;
    private readonly bool _seeInvis;
    private readonly bool _setAttackTarget;

    public PlayerWithinTransition(XElement e)
        : base(e.ParseString("@targetState", "root"))
    {
        _dist = e.ParseFloat("@dist");
        _seeInvis = e.ParseBool("@seeInvis");
        _setAttackTarget = e.ParseBool("@setAttackTarget");
    }
        
    public PlayerWithinTransition(double dist, string targetState, bool seeInvis = false,
        bool setAttackTarget = false)
        : base(targetState)
    {
        _dist = dist;
        _seeInvis = seeInvis;
        _setAttackTarget = setAttackTarget;
    }

    protected override bool TickCore(Entity host, RealmTime time, ref object state)
    {
        var entity = host.GetNearestEntity(_dist, null, _seeInvis);
        if (_setAttackTarget)
            host.AttackTarget = (Player)entity;
        return entity != null;
    }
}