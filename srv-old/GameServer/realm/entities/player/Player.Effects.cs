using Shared;

namespace GameServer.realm.entities.player; 

partial class Player
{
    private float _healing;
    private float _bleeding;

    private long _newbieTime;
    private long _canTpCooldownTime;

    private void HandleEffects(RealmTime time)
    {
        if (_client.Account.Hidden && !HasConditionEffect(ConditionEffects.Hidden))
        {
            ApplyConditionEffect(ConditionEffectIndex.Hidden);
            Manager.Clients[Client].Hidden = true;
        }
            
        if (HasConditionEffect(ConditionEffects.Bleeding) && HP > 1)
        {
            if (_bleeding > 1)
            {
                HP -= (int)_bleeding;
                if (HP < 1)
                    HP = 1;
                _bleeding -= (int)_bleeding;
            }

            _bleeding += 28 * (time.ElapsedUsDelta / (1000f * 1000f));
        }
            
        if (_newbieTime > 0)
        {
            _newbieTime -= time.ElapsedUsDelta;
            if (_newbieTime < 0)
                _newbieTime = 0;
        }

        if (_canTpCooldownTime > 0)
        {
            _canTpCooldownTime -= time.ElapsedUsDelta;
            if (_canTpCooldownTime < 0)
                _canTpCooldownTime = 0;
        }
    }

    private bool CanHpRegen()
    {
        if (HasConditionEffect(ConditionEffects.Sick))
            return false;
        if (HasConditionEffect(ConditionEffects.Bleeding))
            return false;
        return true;
    }

    internal void SetNewbiePeriod()
    {
        _newbieTime = 3 * 1000 * 1000;
    }

    internal void SetTPDisabledPeriod()
    {
        _canTpCooldownTime = 10 * 1000 * 1000; // 10 seconds
    }

    public bool IsVisibleToEnemy()
    {
        if (HasConditionEffect(ConditionEffects.Hidden) || HasConditionEffect(ConditionEffects.Invisible))
            return false;
        
        return _newbieTime <= 0;
    }

    public bool TPCooledDown()
    {
        return _canTpCooldownTime <= 0;
    }
}