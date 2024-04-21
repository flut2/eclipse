using System.Xml.Linq;
using Shared;
using GameServer.realm;

namespace GameServer.logic.behaviors; 

internal class ChangeSize : Behavior
{
    //State storage: cooldown timer

    private int rate;
    private int target;
        
    public ChangeSize(XElement e)
    {
        rate = e.ParseInt("@rate");
        target = e.ParseInt("@target");
    }

    public ChangeSize(int rate, int target)
    {
        this.rate = rate;
        this.target = target;
    }

    protected override void OnStateEntry(Entity host, RealmTime time, ref object state)
    {
        state = 0L;
    }

    protected override void TickCore(Entity host, RealmTime time, ref object state)
    {
        var cool = (long)state;

        if (cool <= 0)
        {
            var size = host.Size;
            if (size != target)
            {
                size = (ushort) (size + rate);
                if ((rate > 0 && size > target) ||
                    (rate < 0 && size < target))
                    size = (ushort) target;

                host.Size = size;
            }
            cool = 150 * 1000;
        }
        else
            cool -= time.ElapsedUsDelta;

        state = cool;
    }
}