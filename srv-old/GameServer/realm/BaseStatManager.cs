using Shared;
using wServer.realm;

namespace GameServer.realm; 

internal class BaseStatManager
{
    private readonly StatsManager _parent;
    private readonly int[] _base;

    public BaseStatManager(StatsManager parent)
    {
        _parent = parent;
        _base = Utils.ResizeArray(
            parent.Owner.Client.Character.Stats,
            StatsManager.STAT_TOTAL_COUNT);

        ReCalculateValues();
    }

    public int[] GetStats()
    {
        return (int[])_base.Clone();
    }

    public int this[int index]
    {
        get => _base[index];
        set
        {
            _base[index] = value;
            _parent.StatChanged(index);
        }
    }

    protected internal void ReCalculateValues(InventoryChangedEventArgs e = null)
    {
    }
}