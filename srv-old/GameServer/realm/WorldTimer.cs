using GameServer.realm.worlds;

namespace GameServer.realm; 

public class WorldTimer
{
    private readonly Action<World, RealmTime> _cb;
    private readonly Func<World, RealmTime, bool> _rcb;
    private readonly long _total;
    private long _remain;

    public WorldTimer(int tickMs, Action<World, RealmTime> callback)
    {
        _remain = _total = tickMs * 1000;
        _cb = callback;
    }
    
    public WorldTimer(int tickMs, Func<World, RealmTime, bool> callback)
    {
        _remain = _total = tickMs * 1000;
        _rcb = callback;
    }
    
    public void Reset()
    {
        _remain = _total;
    }

    public bool Tick(World world, RealmTime time)
    {
        _remain -= time.ElapsedUsDelta;

        if (_remain >= 0)
            return false;

        if (_cb != null)
        {
            _cb(world, time);
            return true;
        }

        return _rcb(world, time);
    }
}