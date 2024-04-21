using Shared;
using GameServer.realm.entities.player;

namespace GameServer.realm.entities; 

public abstract class Character : Entity
{
    public Random Random = new();

    private readonly SV<int> _hp;
    private readonly SV<int> _maximumHP;

    public int HP
    {
        get => _hp.GetValue();
        set => _hp.SetValue(value);
    }

    public int MaximumHP
    {
        get => _maximumHP.GetValue();
        set => _maximumHP.SetValue(value);
    }

    protected Character(RealmManager manager, ushort objType)
        : base(manager, objType)
    {
        _hp = new SV<int>(this, StatsType.HP, 0);
        _maximumHP = new SV<int>(this, StatsType.MaxHP, 0);

        if (ObjectDesc != null)
        {
            if (ObjectDesc.SizeStep != 0)
            {
                var step = Random.Next(0, (ObjectDesc.MaxSize - ObjectDesc.MinSize) / ObjectDesc.SizeStep + 1) *
                           ObjectDesc.SizeStep;
                SetDefaultSize((ushort) (ObjectDesc.MinSize + step));
            }
            else
                SetDefaultSize((ushort) ObjectDesc.MinSize);

            SetConditions();

            HP = ObjectDesc.MaxHP;
            MaximumHP = HP;
        }
    }

    private void SetConditions()
    {
        if (ObjectDesc.Invulnerable)
            ApplyConditionEffect(ConditionEffectIndex.Invulnerable);
    }

    protected override void ExportStats(IDictionary<StatsType, object> stats)
    {
        stats[StatsType.HP] = HP;
        if (this is not Player)
            stats[StatsType.MaxHP] = MaximumHP;
        base.ExportStats(stats);
    }
}