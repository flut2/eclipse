using System.Collections.Concurrent;

namespace GameServer.realm.entities.player; 

public partial class Player
{
    private const int PingPeriod = 3000 * 1000;
    public const int DcThreshold = 12000 * 1000;

    private long _pingTime = -1;
    private long _pongTime = -1;

    private int _cnt;

    private long _sum;
    public long TimeMap { get; private set; }

    private long _latSum;
    public int Latency { get; private set; }

    private readonly List<KeyValuePair<long, byte[]>> _shoot = new();
    private readonly ConcurrentQueue<long> _updateAckTimeout = new();
    private readonly ConcurrentQueue<int> _move = new();
    private bool KeepAlive(RealmTime time) {
         if (_pingTime == -1) {
             _pingTime = time.TotalElapsedUs - PingPeriod;
             _pongTime = time.TotalElapsedUs;
         }

         if (time.TotalElapsedUs - _pongTime > DcThreshold)
         {
             _client.Disconnect("Connection timeout. (KeepAlive)");
             return false;
         }

         if (_shoot.Count > 0)
         {
             if (time.TotalElapsedUs > _shoot[0].Key)
             {
                 _client.Disconnect("Connection timeout. (ShootAck)");
                 return false;
             }
         }

         if (_updateAckTimeout.TryPeek(out var timeout))
         {
             if (time.TotalElapsedUs > timeout)
             {
                 _client.Disconnect("Connection timeout. (UpdateAck)");
                 return false;
             }
         }

         if (time.TotalElapsedUs - _pingTime < PingPeriod)
             return true;

         _pingTime = time.TotalElapsedUs;
         _client.SendPing(time.TotalElapsedUs);
        return UpdateOnPing();
    }

    public void Pong(RealmTime time, long pongTime, long serial)
    {
        _cnt++;

        _sum += time.TotalElapsedUs - pongTime;
        TimeMap = _sum / _cnt;

        _latSum += (time.TotalElapsedUs - serial) / 2;
        Latency = (int)_latSum / _cnt;

        _pongTime = time.TotalElapsedUs;
    }

    private bool UpdateOnPing()
    {
        // renew account lock
        try
        {
            if (!Manager.Database.RenewLock(_client.Account))
                _client.Disconnect("RenewLock failed. (Pong)");
        }
        catch
        {
            _client.Disconnect("RenewLock failed. (Timeout)");
            return false;
        }

        return true;
    }

    public long C2STime(int clientTime)
    {
        return clientTime + TimeMap;
    }

    public long S2CTime(int serverTime)
    {
        return serverTime - TimeMap;
    }

    public void AwaitShootAck(long serverTime, byte[] shots)
    {
        _shoot.Add(new KeyValuePair<long, byte[]>(serverTime + DcThreshold, shots));
    }

    public void ShootAckReceived()
    {
        if (_shoot.Count == 0)
        {
            _client.Disconnect("One too many ShootAcks");
            return;
        }
            
        _shoot.RemoveAt(0);
    }

    public void AwaitUpdateAck(long serverTime)
    {
        _updateAckTimeout.Enqueue(serverTime + DcThreshold);
    }

    public void UpdateAckReceived()
    {
        if (!_updateAckTimeout.TryDequeue(out _))
        {
            _client.Disconnect("One too many UpdateAcks");
        }
    }
    
    public void AwaitMove(int tickId)
    {
        _move.Enqueue(tickId);
    }

    public void MoveReceived(RealmTime time, int clientTickId, long clientTime)
    {
        /*if (!_move.TryDequeue(out var tickId))
        {
            _client.Disconnect("One too many MovePackets");
            return;
        }

        if (tickId != clientTickId)
        {
            _client.Disconnect("[NewTick -> Move] TickIds don't match");
            return;
        }

        if (clientTickId > TickId)
        {
            _client.Disconnect("[NewTick -> Move] Invalid tickId");
            return;
        }

        var lastClientTime = LastClientTime;
        var lastServerTime = LastServerTime;
        LastClientTime = clientTime;
        LastServerTime = time.TotalElapsedMs;

        if (lastClientTime == -1)
            return;

        _clientTimeLog.Enqueue(pkt.Time - lastClientTime);
        _serverTimeLog.Enqueue((int)(time.TotalElapsedMs - lastServerTime));

        if (_clientTimeLog.Count < 30)
            return;

        if (_clientTimeLog.Count > 30)
        {
            int ignore;
            _clientTimeLog.TryDequeue(out ignore);
            _serverTimeLog.TryDequeue(out ignore);
        }

        // calculate average
        var clientDeltaAvg = _clientTimeLog.Sum() / _clientTimeLog.Count;
        var serverDeltaAvg = _serverTimeLog.Sum() / _serverTimeLog.Count;
        var dx = clientDeltaAvg > serverDeltaAvg
            ? clientDeltaAvg - serverDeltaAvg
            : serverDeltaAvg - clientDeltaAvg;
        if (dx > 15)
        {
            Log.Debug(
                $"TickId: {tickId}, Client Delta: {_clientTimeLog.Sum() / _clientTimeLog.Count}, Server Delta: {_serverTimeLog.Sum() / _serverTimeLog.Count}");
        }*/
    }
}