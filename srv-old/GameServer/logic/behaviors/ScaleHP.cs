using System.Xml.Linq;
using GameServer.realm;
using GameServer.realm.entities;
using Shared;

// ScaleHP behavior by Sanusei MPGH
namespace GameServer.logic.behaviors; 

internal class ScaleHp : Behavior
{
    //State storage: scalehp state

    private readonly int _amountPerPlayer;
    private readonly double _amountPerc;
    private readonly int _maxAdditional; // leave as 0 for no limit
    private readonly bool _healAfterMax;
    private readonly int _dist; // leave as 0 for all players
    private readonly int _scaleAfter;
    private readonly bool _inheritHpScaleState;
    private readonly bool _saveHpScaleState;
        
    public ScaleHp(XElement e)
    {
        _amountPerPlayer = e.ParseInt("@amountPerPlayer");
        _amountPerc = e.ParseFloat("@amountPerc");
        _maxAdditional = e.ParseInt("@maxAdditional");
        _healAfterMax = e.ParseBool("@healAfterMax");
        _dist = e.ParseInt("@dist");
        _scaleAfter = e.ParseInt("@scaleAfter", 1);
        _inheritHpScaleState = e.ParseBool("@inheritHpScaleState");
        _saveHpScaleState = e.ParseBool("@saveHpScaleState", true);
    }

    public ScaleHp(int amountPerPlayer, int maxAdditional, double amountPerc = 0, bool healAfterMax = true, int dist = 0, int scaleAfter = 1)
    {
        _amountPerPlayer = amountPerPlayer;
        _amountPerc = amountPerc;
        _maxAdditional = maxAdditional;
        _healAfterMax = healAfterMax;
        _dist = dist;
        _scaleAfter = scaleAfter;
    }

    protected override void OnStateEntry(Entity host, RealmTime time, ref object state)
    {
        var e = host as Enemy;
        if (_inheritHpScaleState && e?.ScaleHpState != null)
        {
            state = e.ScaleHpState;
            return;
        }
        
        state = new ScaleHpState
        {
            PNamesCounted = new List<string>(),
            InitialScaleAmount = _scaleAfter,
            MaxHp = 0,
            HitMaxHp = false,
            Cooldown = 0
        };
        if (_saveHpScaleState)
            e.ScaleHpState = (ScaleHpState)state;
    }

    protected override void TickCore(Entity host, RealmTime time, ref object state)
    {
        var scstate = (ScaleHpState)state;
        if (scstate.Cooldown <= 0)
        {
            scstate.Cooldown = 1000 * 1000;
            if (host is not Enemy e) return;

            if (scstate.MaxHp == 0)
                scstate.MaxHp = e.MaximumHP + _maxAdditional;

            int plrCount;
            foreach (var i in host.Owner.Players)
            {
                if (scstate.PNamesCounted.Contains(i.Value.Name)) continue;
                if (_dist > 0)
                {
                    if (host.Dist(i.Value) < _dist)
                        scstate.PNamesCounted.Add(i.Value.Name);
                }
                else
                    scstate.PNamesCounted.Add(i.Value.Name);
            }
            plrCount = scstate.PNamesCounted.Count;
            if (plrCount > scstate.InitialScaleAmount)
            {
                var amountInc = (plrCount - scstate.InitialScaleAmount) * _amountPerPlayer;
                var percIncrease = (int)((e.MaximumHP + amountInc) * Math.Pow(1 + _amountPerc, plrCount - scstate.InitialScaleAmount));
                scstate.InitialScaleAmount += plrCount - scstate.InitialScaleAmount;

                if (_maxAdditional != 0)
                    amountInc = Math.Min(_maxAdditional, amountInc);

                var newHpMaximum = e.MaximumHP + amountInc + percIncrease;
                var newHp = e.HP + amountInc + percIncrease;

                if (!scstate.HitMaxHp || _healAfterMax)
                {
                    e.HP = newHp;
                    e.MaximumHP = newHpMaximum;
                }
                if (e.MaximumHP >= scstate.MaxHp && _maxAdditional != 0)
                {
                    e.MaximumHP = scstate.MaxHp;
                    scstate.HitMaxHp = true;
                }

                if (e.HP > e.MaximumHP)
                    e.HP = e.MaximumHP;
            }

            if (_saveHpScaleState)
                e.ScaleHpState = scstate;
        }
        else
            scstate.Cooldown -= time.ElapsedUsDelta;

        state = scstate;
    }
}