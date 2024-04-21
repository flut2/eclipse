using System.Xml.Linq;
using Shared;
using GameServer.realm;
using GameServer.realm.worlds.logic;

namespace GameServer.logic.behaviors; 

internal class OrderOn : Behavior
{
    //State storage: none

    private readonly string _condition;
    private readonly double _range;
    private readonly ushort _children;
    private readonly string _targetStateName;
    private State _targetState;

    public OrderOn(XElement e)
    {
        _condition = e.ParseString("@condition");
        _range = e.ParseFloat("@range");
        _children = GetObjType(e.ParseString("@children"));
        _targetStateName = e.ParseString("@targetState");
    }

    public OrderOn(string condition, double range, string children, string targetState)
    {
        _condition = condition;
        _range = range;
        _children = GetObjType(children);
        _targetStateName = targetState;
    }

    protected override void TickCore(Entity host, RealmTime time, ref object state) {
        _targetState ??= Order.FindState(host.Manager.Behaviors.Definitions[_children].Item1,
            _targetStateName);

        foreach (var i in host.GetNearestEntities(_range, _children))
            if (!i.CurrentState.Is(_targetState))
                i.SwitchTo(_targetState);
    }
}