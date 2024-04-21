using System.Xml.Linq;
using Shared;
using GameServer.realm;
using GameServer.realm.entities;

namespace GameServer.logic.transitions; 

public class DamageTakenTransition : Transition
{
    //State storage: hp/max hp

    private int _damage;
    private bool _fromMaxHp;

    public DamageTakenTransition(XElement e)
        : base(e.ParseString("@targetState", "root"))
    {
        _damage = e.ParseInt("@damage");
        _fromMaxHp = e.ParseBool("@fromMaxHp");
    }
        
    public DamageTakenTransition(int damage, string targetState, bool fromMaxHp = false)
        : base(targetState)
    {
        _damage = damage;
        _fromMaxHp = fromMaxHp;
    }

    protected override void OnStateEntry(Entity host, RealmTime time, ref object state)
    {
        state = _fromMaxHp ? ((Enemy)host).MaximumHP : ((Enemy)host).HP;
    }

    protected override bool TickCore(Entity host, RealmTime time, ref object state)
    {
        return (int)state - ((Enemy)host).HP >= _damage;
    }
}