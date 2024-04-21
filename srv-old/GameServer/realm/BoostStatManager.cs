using Shared;
using Shared.resources;
using GameServer.realm.entities.player;
using wServer.realm;

namespace GameServer.realm; 

internal class BoostStatManager
{
    private readonly StatsManager _parent;
    private readonly Player _player;
    private readonly SV<ushort>[] _boostSV;
    private readonly ushort[] _boost;
    private readonly ActivateBoost[] _activateBoost;

    public ActivateBoost[] ActivateBoost => _activateBoost;
    public ushort this[int index] => _boost[index];

    public BoostStatManager(StatsManager parent)
    {
        _parent = parent;
        _player = parent.Owner;

        _boost = new ushort[StatsManager.STAT_TOTAL_COUNT];
        _boostSV = new SV<ushort>[_boost.Length];
        for (var i = 0; i < _boostSV.Length; i++)
            _boostSV[i] = new SV<ushort>(_player, StatsManager.GetBoostStatType(i), _boost[i], i != 0 && i != 1);
        _activateBoost = new ActivateBoost[_boost.Length];
        for (var i = 0; i < _activateBoost.Length; i++)
            _activateBoost[i] = new ActivateBoost();
        ReCalculateValues();
    }

    protected internal void ReCalculateValues(InventoryChangedEventArgs e = null)
    {
        for (var i = 0; i < _boost.Length; i++)
            _boost[i] = 0;

        ApplyEquipBonus(e);
        ApplyActivateBonus(e);

        for (var i = 0; i < _boost.Length; i++)
            _boostSV[i].SetValue(_boost[i]);
    }

    private void ApplyEquipBonus(InventoryChangedEventArgs e)
    {
        for (var i = 0; i < 6; i++)
        {
            if (_player.Inventory[i] == null)
                continue;

            foreach (var boost in _player.Inventory[i].StatsBoost)
                IncrementBoost((StatsType)boost.Key, boost.Value);
                
            foreach (var pBoost in _player.Inventory[i].StatsBoostPerc)
                IncrementBoost((StatsType)pBoost.Key, (int)(_parent.Base[StatsManager.GetStatIndex((StatsType)pBoost.Key)] * pBoost.Value));
        }
    }
        
    private void ApplyActivateBonus(InventoryChangedEventArgs e)
    {
        for (var i = 0; i < _activateBoost.Length; i++)
        {
            // set boost
            var b = _activateBoost[i].GetBoost();
            _boost[i] += (ushort)b;

            if (i > 7 && i != 12 && i != 19 && i != 20)
                continue;

            // set condition icon
            var idx = i + 31;
            switch (i)
            {
                case 12:
                    idx = 42;
                    break;
                case 19:
                    idx = 49;
                    break;
                case 20:
                    idx = 50;
                    break;
            }
            var haveCondition = _player.HasConditionEffect((ConditionEffects)((ulong)1 << idx));
            if (b > 0)
            {
                if (!haveCondition)
                    _player.ApplyConditionEffect(new ConditionEffect()
                    {
                        Effect = (ConditionEffectIndex)idx,
                        DurationMS = -1
                    });
            }
            else
            {
                if (haveCondition)
                    _player.ApplyConditionEffect(new ConditionEffect()
                    {
                        Effect = (ConditionEffectIndex)idx,
                        DurationMS = 0
                    });
            }
        }
    }

    private void IncrementBoost(StatsType stat, int amount)
    {
        var i = StatsManager.GetStatIndex(stat);
        if (_parent.Base[i] + amount < 1)
        {
            _boost[i] += (ushort)(i == 0 ? -_parent.Base[i] + 1 : -_parent.Base[i]);
            return;
        }

        _boost[i] += (ushort)amount;
    }

    private void FixedStat(StatsType stat, int value)
    {
        var i = StatsManager.GetStatIndex(stat);
        _boost[i] = (ushort)(value - _parent.Base[i]);
    }
}