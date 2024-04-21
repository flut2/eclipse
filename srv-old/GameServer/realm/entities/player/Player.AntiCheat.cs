using Shared;
using NLog;

namespace GameServer.realm.entities.player; 

partial class Player
{
    internal const int MaxToleranceMs = 1000;
    private static readonly Logger CheatLog = LogManager.GetLogger("CheatLog");

    // hit
    public long AcLastHitTime;
    public int AcShotsHit;
    public int AcMissedShots;
    private int _acLastMissReset;
    // shoot
    public long AcClientLastShot;
    public int AcShotNum;
    // move
    public bool[] AcIgnoreLastMove = new bool[256];
    public byte AcLastMoveId;
    public Position[] AcLastMove = new Position[256];
    public int AcMoveInfractions;
    private int _acMoveRefreshTime;

    public bool IsNoClipping()
    {
        if (Owner == null || !TileOccupied(RealX, RealY) && !TileFullOccupied(RealX, RealY))
            return false;

        CheatLog.Info($"{Name} is walking on an occupied tile.");
        return true;
    }

    public bool IsInvalidTime(long serverTime, int clientTime)
    {
        var estimatedServerTime = C2STime(clientTime);
        return estimatedServerTime > serverTime + MaxToleranceMs || estimatedServerTime - MaxToleranceMs > serverTime;
    }
}