namespace GameServer.logic; 

internal struct Cooldown
{
    public readonly long CoolDown;
    public readonly long Variance;

    public Cooldown(long cooldown, long variance)
    {
        this.CoolDown = cooldown;
        this.Variance = variance;
    }

    public Cooldown Normalize()
    {
        if (CoolDown == 0)
            return 1000 * 1000;
        else
            return this;
    }

    public Cooldown Normalize(long def)
    {
        if (CoolDown == 0)
            return def;
        else
            return this;
    }

    public long Next(Random rand)
    {
        if (Variance == 0)
            return CoolDown;

        return CoolDown + rand.NextInt64(-Variance, Variance + 1);
    }

    public static implicit operator Cooldown(long cooldown)
    {
        return new Cooldown(cooldown, 0);
    }
}