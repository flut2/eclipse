using System.Xml.Linq;
using Shared;
using GameServer.realm;

namespace GameServer.logic.behaviors; 

//replacement for simple timed transition in sequence
internal class Timed : CycleBehavior
{
    //State storage: time

    private Behavior[] behaviors;
    private long period;
        
    public Timed(XElement e, IStateChildren[] children)
    {
        var behaviors = new List<Behavior>();
        foreach (var child in children)
        {
            if (child is Behavior bh)
                behaviors.Add(bh);
        }

        this.behaviors = behaviors.ToArray();
        period = e.ParseLong("@period") * 1000;
    }

    protected override void OnStateEntry(Entity host, RealmTime time, ref object state)
    {
        foreach(var behavior in behaviors)
            behavior.OnStateEntry(host, time);
        state = period;
    }

    protected override void TickCore(Entity host, RealmTime time, ref object state)
    {
        var period = (long)state;
            
        foreach (var behavior in behaviors)
        {   behavior.Tick(host, time);
            Status = CycleStatus.InProgress;

            period -= time.ElapsedUsDelta;
            if (period <= 0)
            {
                period = this.period;
                Status = CycleStatus.Completed;
                //......- -
                if (behavior is Prioritize)
                    host.StateStorage[behavior] = -1;
            }
        }
        state = period;
    }
}