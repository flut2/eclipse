using System.Xml.Linq;
using Shared;
using GameServer.realm;

namespace GameServer.logic.transitions; 

internal class TimedRandomTransition : Transition
{
    //State storage: cooldown timer

    private readonly int _time;
    private readonly bool _randomized;

    public TimedRandomTransition(XElement e)
        : base(e.ParseStringArray("@targetStates", ',', new [] {"root"}))
    {
        _time = e.ParseInt("@time") * 1000;
        _randomized = e.ParseBool("@randomizedTime");
    }

    protected override bool TickCore(Entity host, RealmTime time, ref object state)
    {
        long cool;

        if (state == null)
            cool = _randomized ? Random.Next(_time) : _time;
        else
            cool = (int)state;

        if (cool <= 0)
        {
            state = _time;
            SelectedState = Random.Next(TargetStates.Length);
            return true;
        }

        cool -= time.ElapsedUsDelta;
        state = cool;
        return false;
    }
}