using System.Buffers.Binary;
using System.Net;
using System.Net.Sockets;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using Shared;
using Shared.resources;
using GameServer.realm;
using GameServer.realm.entities;
using GameServer.realm.entities.player;
using GameServer.realm.entities.vendors;
using GameServer.realm.worlds;
using GameServer.realm.worlds.logic;
using K4os.Compression.LZ4;
using K4os.Compression.LZ4.Encoders;
using NLog;
using StackExchange.Redis;
using wServer.realm;
using static GameServer.PacketUtils;

namespace GameServer;

public enum FailureType : sbyte {
    MessageNoDisconnect = -1,
    MessageWithDisconnect = 0,
    ClientUpdateNeeded = 1,
    ForceCloseGame = 2,
    InvalidTeleportTarget = 3
}

public enum C2SPacketId : byte {
    Unknown = 0,
    PlayerShoot = 1,
    Move = 2,
    PlayerText = 3,
    UpdateAck = 4,
    InvSwap = 5,
    UseItem = 6,
    Hello = 7,
    InvDrop = 8,
    Pong = 9,
    Teleport = 10,
    UsePortal = 11,
    Buy = 12,
    GroundDamage = 13,
    PlayerHit = 14,
    EnemyHit = 15,
    AoeAck = 16,
    ShootAck = 17,
    OtherHit = 18,
    SquareHit = 19,
    EditAccountList = 20,
    CreateGuild = 21,
    GuildRemove = 22,
    GuildInvite = 23,
    RequestTrade = 24,
    ChangeTrade = 25,
    AcceptTrade = 26,
    CancelTrade = 27,
    Escape = 28,
    JoinGuild = 29,
    ChangeGuildRank = 30,
    Reskin = 31,
    MapHello = 32,
    UseAbility = 33
};

public enum S2CPacketId : byte {
    Unknown = 0,
    CreateSuccess = 1,
    Text = 2,
    ServerPlayerShoot = 3,
    Damage = 4,
    Update = 5,
    Notification = 6,
    NewTick = 7,
    ShowEffect = 8,
    Goto = 9,
    InvResult = 10,
    Ping = 11,
    MapInfo = 12,
    Death = 13,
    BuyResult = 14,
    Aoe = 15,
    AccountList = 16,
    QuestObjId = 17,
    GuildResult = 18,
    AllyShoot = 19,
    EnemyShoot = 20,
    TradeRequested = 21,
    TradeStart = 22,
    TradeChanged = 23,
    TradeDone = 24,
    TradeAccepted = 25,
    InvitedToGuild = 26,
    PlaySound = 27,
    Failure = 28
};

public class Client {
    private const int LENGTH_PREFIX = 2;
    
    private static Logger Log = LogManager.GetCurrentClassLogger();
    public Random ClientRandom = new((int) DateTime.Now.Ticks);
    public static Random StaticRandom = new((int) DateTime.Now.Ticks);
    private Server _server;
    public DbAccount Account;
    public DbChar Character;
    public string IP;
    public RealmManager Manager;
    public Player Player;
    public Socket Socket;
    private Memory<byte> ReceiveMem;
    private Memory<byte> SendMem;
    private const int PingPeriod = 3000;
    private const int DcThresold = 15000;
    private long _pingTime = -1L;
    private long _pongTime = -1L;
    private int _serial;

    public Client(Server server, RealmManager manager) {
        _server = server;
        Manager = manager;
        ReceiveMem = GC.AllocateArray<byte>(RECV_BUFFER_LEN, pinned: true).AsMemory();
        SendMem = GC.AllocateArray<byte>(SEND_BUFFER_LEN, pinned: true).AsMemory();
    }

    private void Receive() {
        if (!Socket.Connected)
            return;

        try {
            while (Socket.Connected) {
                var len = Socket.Receive(ReceiveMem.Span);
                if (len > 0)
                    ProcessPacket(len);
            }
        }
        catch (Exception e) {
            Disconnect();
            if (e is not SocketException se || (se.SocketErrorCode != SocketError.ConnectionReset &&
                                                se.SocketErrorCode != SocketError.Shutdown))
                Log.Error($"Could not receive data from {Account?.Name ?? "[unconnected]"} ({IP}): {e}");
        }
    }

    public void Reset(Socket socket) {
        Account = null;
        Character = null;
        Player = null;
        _pingTime = _pongTime = -1L;
        Socket = socket;
        try {
            IP = ((IPEndPoint) socket.RemoteEndPoint).Address.ToString();
        }
        catch (Exception) {
            IP = "";
        }

        Log.Trace("Received client @ {0}.", IP);
        Receive();
    }

    private void TrySend(int len) {
        if (!Socket.Connected)
            return;

        try {
            // Log.Error($"Sending packet {(S2CPacketId) SendMem.Span[LENGTH_PREFIX]} {len}");
            BinaryPrimitives.WriteUInt16LittleEndian(SendMem.Span, (ushort)(len - 2));
            Socket.Send(SendMem.Span[..len]);
        }
        catch (Exception e) {
            Disconnect();
            if (e is not SocketException se || (se.SocketErrorCode != SocketError.ConnectionReset &&
                                                se.SocketErrorCode != SocketError.Shutdown))
                Log.Error($"{Account?.Name ?? "[unconnected]"} ({IP}): {e}");
        }
    }

    public void SendAccountList(int id, int[] list) {
        var ptr = LENGTH_PREFIX;
        ref var spanRef = ref MemoryMarshal.GetReference(SendMem.Span);
        WriteByte(ref ptr, ref spanRef, (byte) S2CPacketId.AccountList);
        WriteInt(ref ptr, ref spanRef, id);
        WriteShort(ref ptr, ref spanRef, (short) list.Length);
        foreach (var i in list)
            WriteInt(ref ptr, ref spanRef, i);

        TrySend(ptr);
    }

    public void SendAllyShoot(byte bulletId, int ownerId, ushort containerType, float angle) {
        var ptr = LENGTH_PREFIX;
        ref var spanRef = ref MemoryMarshal.GetReference(SendMem.Span);
        WriteByte(ref ptr, ref spanRef, (byte) S2CPacketId.AllyShoot);
        WriteByte(ref ptr, ref spanRef, bulletId);
        WriteInt(ref ptr, ref spanRef, ownerId);
        WriteUShort(ref ptr, ref spanRef, containerType);
        WriteFloat(ref ptr, ref spanRef, angle);
        TrySend(ptr);
    }

    public void SendAOE(float x, float y, float radius, ushort damage, ConditionEffectIndex effect, float duration,
        ushort origType, uint color) {
        var ptr = LENGTH_PREFIX;
        ref var spanRef = ref MemoryMarshal.GetReference(SendMem.Span);
        WriteByte(ref ptr, ref spanRef, (byte) S2CPacketId.Aoe);
        WriteFloat(ref ptr, ref spanRef, x);
        WriteFloat(ref ptr, ref spanRef, y);
        WriteFloat(ref ptr, ref spanRef, radius);
        WriteUShort(ref ptr, ref spanRef, damage);
        WriteByte(ref ptr, ref spanRef, (byte) effect);
        WriteFloat(ref ptr, ref spanRef, duration);
        WriteUShort(ref ptr, ref spanRef, origType);
        WriteUInt(ref ptr, ref spanRef, color);
        TrySend(ptr);
    }

    public void SendBuyResult(int id, string res) {
        var ptr = LENGTH_PREFIX;
        ref var spanRef = ref MemoryMarshal.GetReference(SendMem.Span);
        WriteByte(ref ptr, ref spanRef, (byte) S2CPacketId.BuyResult);
        WriteInt(ref ptr, ref spanRef, id);
        WriteString(ref ptr, ref spanRef, res);
        TrySend(ptr);
    }

    public void SendCreateSuccess(int objId, int charId) {
        var ptr = LENGTH_PREFIX;
        ref var spanRef = ref MemoryMarshal.GetReference(SendMem.Span);
        WriteByte(ref ptr, ref spanRef, (byte) S2CPacketId.CreateSuccess);
        WriteInt(ref ptr, ref spanRef, objId);
        WriteInt(ref ptr, ref spanRef, charId);
        TrySend(ptr);
    }

    public void SendDamage(int targetId, ConditionEffects effects, ushort damage, bool kill, byte bulletId,
        int objectId) {
        var ptr = LENGTH_PREFIX;
        ref var spanRef = ref MemoryMarshal.GetReference(SendMem.Span);
        WriteByte(ref ptr, ref spanRef, (byte) S2CPacketId.Damage);
        WriteInt(ref ptr, ref spanRef, targetId);
        WriteUInt(ref ptr, ref spanRef, (uint) (int) effects);
        WriteUShort(ref ptr, ref spanRef, damage);
        WriteBool(ref ptr, ref spanRef, kill);
        WriteByte(ref ptr, ref spanRef, bulletId);
        WriteInt(ref ptr, ref spanRef, objectId);
        TrySend(ptr);
    }

    public void SendDeath(int accId, int charId, string killedBy) {
        var ptr = LENGTH_PREFIX;
        ref var spanRef = ref MemoryMarshal.GetReference(SendMem.Span);
        WriteByte(ref ptr, ref spanRef, (byte) S2CPacketId.Death);
        WriteInt(ref ptr, ref spanRef, accId);
        WriteInt(ref ptr, ref spanRef, charId);
        WriteString(ref ptr, ref spanRef, killedBy);
        TrySend(ptr);
    }

    public void SendEnemyShoot(byte bulletId, int ownerId, byte bulletType, float x, float y, float angle, short damage, short magicDamage, short trueDamage,
        byte numShots, float angleInc) {
        var ptr = LENGTH_PREFIX;
        ref var spanRef = ref MemoryMarshal.GetReference(SendMem.Span);
        WriteByte(ref ptr, ref spanRef, (byte) S2CPacketId.EnemyShoot);
        WriteByte(ref ptr, ref spanRef, bulletId);
        WriteInt(ref ptr, ref spanRef, ownerId);
        WriteByte(ref ptr, ref spanRef, bulletType);
        WriteFloat(ref ptr, ref spanRef, x);
        WriteFloat(ref ptr, ref spanRef, y);
        WriteFloat(ref ptr, ref spanRef, angle);
        WriteShort(ref ptr, ref spanRef, damage);
        WriteShort(ref ptr, ref spanRef, magicDamage);
        WriteShort(ref ptr, ref spanRef, trueDamage);
        WriteByte(ref ptr, ref spanRef, numShots);
        WriteFloat(ref ptr, ref spanRef, angleInc);
        TrySend(ptr);
    }

    public void SendGoto(int objId, float x, float y) {
        var ptr = LENGTH_PREFIX;
        ref var spanRef = ref MemoryMarshal.GetReference(SendMem.Span);
        WriteByte(ref ptr, ref spanRef, (byte) S2CPacketId.Goto);
        WriteInt(ref ptr, ref spanRef, objId);
        WriteFloat(ref ptr, ref spanRef, x);
        WriteFloat(ref ptr, ref spanRef, y);
        TrySend(ptr);
    }

    public void SendGuildResult(bool success, string errorText) {
        var ptr = LENGTH_PREFIX;
        ref var spanRef = ref MemoryMarshal.GetReference(SendMem.Span);
        WriteByte(ref ptr, ref spanRef, (byte) S2CPacketId.GuildResult);
        WriteBool(ref ptr, ref spanRef, success);
        WriteString(ref ptr, ref spanRef, errorText);
        TrySend(ptr);
    }

    public void SendInvitedToGuild(string guildName, string name) {
        var ptr = LENGTH_PREFIX;
        ref var spanRef = ref MemoryMarshal.GetReference(SendMem.Span);
        WriteByte(ref ptr, ref spanRef, (byte) S2CPacketId.InvitedToGuild);
        WriteString(ref ptr, ref spanRef, guildName);
        WriteString(ref ptr, ref spanRef, name);
        TrySend(ptr);
    }

    public void SendInvResult(byte result) {
        var ptr = LENGTH_PREFIX;
        ref var spanRef = ref MemoryMarshal.GetReference(SendMem.Span);
        WriteByte(ref ptr, ref spanRef, (byte) S2CPacketId.InvResult);
        WriteByte(ref ptr, ref spanRef, result);
        TrySend(ptr);
    }

    public void SendMapInfo(int width, int height, string name, int bgLightColor, float bgLightIntensity,
        bool allowTp, float dayLightIntensity, float nightLightIntensity) {
        var ptr = LENGTH_PREFIX;
        ref var spanRef = ref MemoryMarshal.GetReference(SendMem.Span);
        WriteByte(ref ptr, ref spanRef, (byte) S2CPacketId.MapInfo);
        WriteInt(ref ptr, ref spanRef, width);
        WriteInt(ref ptr, ref spanRef, height);
        WriteString(ref ptr, ref spanRef, name);
        WriteInt(ref ptr, ref spanRef, bgLightColor);
        WriteFloat(ref ptr, ref spanRef, bgLightIntensity);
        WriteBool(ref ptr, ref spanRef, allowTp);
        WriteBool(ref ptr, ref spanRef, dayLightIntensity != 0);
        if (dayLightIntensity != 0) {
            WriteFloat(ref ptr, ref spanRef, dayLightIntensity);
            WriteFloat(ref ptr, ref spanRef, nightLightIntensity);
            WriteLong(ref ptr, ref spanRef, Manager.Logic.WorldTime.TotalElapsedUs);
        }
        TrySend(ptr);
    }

    public void SendNewTick(byte tickId, byte tps, ObjectStats[] stats) {
        var ptr = LENGTH_PREFIX;
        ref var spanRef = ref MemoryMarshal.GetReference(SendMem.Span);
        WriteByte(ref ptr, ref spanRef, (byte) S2CPacketId.NewTick);
        WriteByte(ref ptr, ref spanRef, tickId);
        WriteByte(ref ptr, ref spanRef, tps);
        WriteShort(ref ptr, ref spanRef, (short) stats.Length);
        for (var i = 0; i < stats.Length; i++) {
            var stat = stats[i];
            WriteInt(ref ptr, ref spanRef, stat.Id);
            WriteFloat(ref ptr, ref spanRef, stat.X);
            WriteFloat(ref ptr, ref spanRef, stat.Y);
            var statTypes = stat.StatTypes;
            if (statTypes == null) {
                WriteUShort(ref ptr, ref spanRef, 0);
                continue;
            }

            var lengthPtr = ptr;
            WriteUShort(ref ptr, ref spanRef, 0);
            foreach (var (key, value) in statTypes)
                SendStat(ref ptr, ref spanRef, key, value);
            WriteUShort(ref lengthPtr, ref spanRef, (ushort)(ptr - lengthPtr - 2));
        }

        TrySend(ptr);
    }

    public void SendNotification(int objId, string msg, uint color) {
        var ptr = LENGTH_PREFIX;
        ref var spanRef = ref MemoryMarshal.GetReference(SendMem.Span);
        WriteByte(ref ptr, ref spanRef, (byte) S2CPacketId.Notification);
        WriteInt(ref ptr, ref spanRef, objId);
        WriteString(ref ptr, ref spanRef, msg);
        WriteUInt(ref ptr, ref spanRef, color);
        TrySend(ptr);
    }

    public void SendPing(long serial) {
        var ptr = LENGTH_PREFIX;
        ref var spanRef = ref MemoryMarshal.GetReference(SendMem.Span);
        WriteByte(ref ptr, ref spanRef, (byte) S2CPacketId.Ping);
        WriteLong(ref ptr, ref spanRef, serial);
        TrySend(ptr);
    }

    public void SendShowEffect(EffectType effectType, int targetObjId, float x1, float y1, float x2, float y2,
        uint color) {
        var ptr = LENGTH_PREFIX;
        ref var spanRef = ref MemoryMarshal.GetReference(SendMem.Span);
        WriteByte(ref ptr, ref spanRef, (byte) S2CPacketId.ShowEffect);
        WriteByte(ref ptr, ref spanRef, (byte) effectType);
        WriteInt(ref ptr, ref spanRef, targetObjId);
        WriteFloat(ref ptr, ref spanRef, x1);
        WriteFloat(ref ptr, ref spanRef, y1);
        WriteFloat(ref ptr, ref spanRef, x2);
        WriteFloat(ref ptr, ref spanRef, y2);
        WriteUInt(ref ptr, ref spanRef, color);
        TrySend(ptr);
    }

    public void SendText(string name, int objectId, byte bubbleTime, string recipient, string text,
        uint nameColor = 0xFF0000, uint textColor = 0xFFFFFF) {
        var ptr = LENGTH_PREFIX;
        ref var spanRef = ref MemoryMarshal.GetReference(SendMem.Span);
        WriteByte(ref ptr, ref spanRef, (byte) S2CPacketId.Text);
        WriteString(ref ptr, ref spanRef, name);
        WriteInt(ref ptr, ref spanRef, objectId);
        WriteByte(ref ptr, ref spanRef, bubbleTime);
        WriteString(ref ptr, ref spanRef, recipient);
        WriteString(ref ptr, ref spanRef, text);
        if (text != "")
            WriteUInt(ref ptr, ref spanRef, textColor);
        if (name != "")
            WriteUInt(ref ptr, ref spanRef, nameColor);
        TrySend(ptr);
    }

    public void SendTradeAccepted(bool[] myOffer, bool[] yourOffer) {
        var ptr = LENGTH_PREFIX;
        ref var spanRef = ref MemoryMarshal.GetReference(SendMem.Span);
        WriteByte(ref ptr, ref spanRef, (byte) S2CPacketId.TradeAccepted);
        WriteShort(ref ptr, ref spanRef, (short) myOffer.Length);
        foreach (var offer in myOffer)
            WriteBool(ref ptr, ref spanRef, offer);

        WriteShort(ref ptr, ref spanRef, (short) yourOffer.Length);
        foreach (var offer2 in yourOffer)
            WriteBool(ref ptr, ref spanRef, offer2);

        TrySend(ptr);
    }

    public void SendTradeChanged(bool[] offer) {
        var ptr = LENGTH_PREFIX;
        ref var spanRef = ref MemoryMarshal.GetReference(SendMem.Span);
        WriteByte(ref ptr, ref spanRef, (byte) S2CPacketId.TradeChanged);
        WriteShort(ref ptr, ref spanRef, (short) offer.Length);
        foreach (var o in offer)
            WriteBool(ref ptr, ref spanRef, o);

        TrySend(ptr);
    }

    public void SendTradeDone(int code, string desc) {
        var ptr = LENGTH_PREFIX;
        ref var spanRef = ref MemoryMarshal.GetReference(SendMem.Span);
        WriteByte(ref ptr, ref spanRef, (byte) S2CPacketId.TradeDone);
        WriteInt(ref ptr, ref spanRef, code);
        WriteString(ref ptr, ref spanRef, desc);
        TrySend(ptr);
    }

    public void SendTradeRequested(string name) {
        var ptr = LENGTH_PREFIX;
        ref var spanRef = ref MemoryMarshal.GetReference(SendMem.Span);
        WriteByte(ref ptr, ref spanRef, (byte) S2CPacketId.TradeRequested);
        WriteString(ref ptr, ref spanRef, name);
        TrySend(ptr);
    }

    public void SendTradeStart(TradeItem[] myItems, string yourName, TradeItem[] yourItems) {
        var ptr = LENGTH_PREFIX;
        ref var spanRef = ref MemoryMarshal.GetReference(SendMem.Span);
        WriteByte(ref ptr, ref spanRef, (byte) S2CPacketId.TradeStart);
        WriteShort(ref ptr, ref spanRef, (short) myItems.Length);
        for (var i = 0; i < myItems.Length; i++) {
            var offer = myItems[i];
            WriteInt(ref ptr, ref spanRef, offer.Item);
            WriteInt(ref ptr, ref spanRef, offer.SlotType);
            WriteBool(ref ptr, ref spanRef, offer.Tradeable);
            WriteBool(ref ptr, ref spanRef, offer.Included);
        }

        WriteString(ref ptr, ref spanRef, yourName);
        WriteShort(ref ptr, ref spanRef, (short) yourItems.Length);
        for (var j = 0; j < yourItems.Length; j++) {
            var offer2 = yourItems[j];
            WriteInt(ref ptr, ref spanRef, offer2.Item);
            WriteInt(ref ptr, ref spanRef, offer2.SlotType);
            WriteBool(ref ptr, ref spanRef, offer2.Tradeable);
            WriteBool(ref ptr, ref spanRef, offer2.Included);
        }

        TrySend(ptr);
    }

    public void SendUpdate(TileData[] tiles, ObjectDef[] newObjs, int[] drops) {
        var ptr = LENGTH_PREFIX;
        ref var spanRef = ref MemoryMarshal.GetReference(SendMem.Span);
        WriteByte(ref ptr, ref spanRef, (byte) S2CPacketId.Update);
        WriteShort(ref ptr, ref spanRef, (short) tiles.Length);
        for (var i = 0; i < tiles.Length; i++) {
            var tile = tiles[i];
            WriteUShort(ref ptr, ref spanRef, tile.X);
            WriteUShort(ref ptr, ref spanRef, tile.Y);
            WriteUShort(ref ptr, ref spanRef, tile.Tile);
        }
        
        WriteShort(ref ptr, ref spanRef, (short) drops.Length);
        foreach (var drop in drops)
            WriteInt(ref ptr, ref spanRef, drop);

        WriteShort(ref ptr, ref spanRef, (short) newObjs.Length);
        for (var j = 0; j < newObjs.Length; j++) {
            var newObj = newObjs[j];
            WriteUShort(ref ptr, ref spanRef, newObj.ObjectType);
            WriteInt(ref ptr, ref spanRef, newObj.Stats.Id);
            WriteFloat(ref ptr, ref spanRef, newObj.Stats.X);
            WriteFloat(ref ptr, ref spanRef, newObj.Stats.Y);
            var statTypes = newObj.Stats.StatTypes;
            if (statTypes == null) {
                WriteUShort(ref ptr, ref spanRef, 0);
                continue;
            }

            var lengthPtr = ptr;
            WriteUShort(ref ptr, ref spanRef, 0);
            foreach (var (key, value) in statTypes)
                SendStat(ref ptr, ref spanRef, key, value);
            WriteUShort(ref lengthPtr, ref spanRef, (ushort)(ptr - lengthPtr - 2));
        }

        TrySend(ptr);
    }

    public static void SendStat(ref int ptr, ref byte spanRef, StatsType stat, object value) {
        WriteByte(ref ptr, ref spanRef, (byte) stat);
        switch (stat) {
            case StatsType.PortalUsable:
                WriteBool(ref ptr, ref spanRef, Convert.ToInt32(value) == 1);
                return;
            case StatsType.MerchPrice:
            case StatsType.Tier:
                WriteByte(ref ptr, ref spanRef, Convert.ToByte(value));
                return;
            case StatsType.MerchCount:
            case StatsType.GuildRank:
                WriteSByte(ref ptr, ref spanRef, Convert.ToSByte(value));
                return;
            case StatsType.MaxMP:
            case StatsType.MP:
            case StatsType.Strength:
            case StatsType.Wit:
            case StatsType.Defense:
            case StatsType.Resistance:
            case StatsType.Speed:
            case StatsType.Stamina:
            case StatsType.Intelligence:
            case StatsType.Penetration:
            case StatsType.Piercing:
            case StatsType.Haste:
            case StatsType.Tenacity:
            case StatsType.HPBonus:
            case StatsType.MPBonus:
            case StatsType.StrengthBonus:
            case StatsType.WitBonus:
            case StatsType.DefenseBonus:
            case StatsType.ResistanceBonus:
            case StatsType.SpeedBonus:
            case StatsType.StaminaBonus:
            case StatsType.IntelligenceBonus:
            case StatsType.PenetrationBonus:
            case StatsType.PiercingBonus:
            case StatsType.HasteBonus:
            case StatsType.TenacityBonus:
            case StatsType.SellablePrice:
                WriteShort(ref ptr, ref spanRef, Convert.ToInt16(value));
                return;
            case StatsType.Size:
            case StatsType.Inv0:
            case StatsType.Inv1:
            case StatsType.Inv2:
            case StatsType.Inv3:
            case StatsType.Inv4:
            case StatsType.Inv5:
            case StatsType.Inv6:
            case StatsType.Inv7:
            case StatsType.Inv8:
            case StatsType.Inv9:
            case StatsType.Inv10:
            case StatsType.Inv11:
            case StatsType.Inv12:
            case StatsType.Inv13:
            case StatsType.Inv14:
            case StatsType.Inv15:
            case StatsType.Inv16:
            case StatsType.Inv17:
            case StatsType.Inv18:
            case StatsType.Inv19:
            case StatsType.Inv20:
            case StatsType.Inv21:
            case StatsType.MerchType:
            case StatsType.AltTextureIndex:
            case StatsType.Texture:
                WriteUShort(ref ptr, ref spanRef, Convert.ToUInt16(value));
                return;
            case StatsType.MaxHP:
            case StatsType.HP:
            case StatsType.Gems:
            case StatsType.AccountId:
            case StatsType.Gold:
            case StatsType.Crowns:
            case StatsType.OwnerAccountId:
                WriteInt(ref ptr, ref spanRef, Convert.ToInt32(value));
                return;
            case StatsType.Condition:
                WriteUInt(ref ptr, ref spanRef, Convert.ToUInt32(value));
                return;
            case StatsType.Name:
            case StatsType.Guild:
                WriteString(ref ptr, ref spanRef, (string) value);
                return;
            case StatsType.DamageMultiplier:
            case StatsType.HitMultiplier:
                WriteFloat(ref ptr, ref spanRef, Convert.ToSingle(value));
                return;
            case StatsType.Texture1:
            case StatsType.Texture2:
            case StatsType.None:
                return;
        }

        Log.Error($"Unhandled stat {stat}, value: {value}");
    }

    public void Reconnect(string name, int gameId) {
        if (Account == null) {
            Disconnect("Tried to reconnect an client with a null account...");
            return;
        }

        Log.Trace("Reconnecting client ({0}) @ {1} to {2}...", Account.Name, IP, name);
        ConnectManager.Reconnect(this, gameId);
    }

    public void SendFailure(string text, FailureType errorId = FailureType.MessageWithDisconnect, bool disconnect = true) {
        var ptr = LENGTH_PREFIX;
        ref var spanRef = ref MemoryMarshal.GetReference(SendMem.Span);
        WriteByte(ref ptr, ref spanRef, (byte) S2CPacketId.Failure);
        WriteSByte(ref ptr, ref spanRef, (sbyte) errorId);
        WriteString(ref ptr, ref spanRef, text);
        TrySend(ptr);
        if (disconnect && (errorId == FailureType.MessageWithDisconnect || errorId == FailureType.ForceCloseGame))
            Disconnect();
    }

    private static bool ValidateEntities(Player p, Entity a, Entity b) {
        if (a == null || b == null || a is not IContainer || b is not IContainer || (a is Player && a != p) ||
            (b is Player && b != p) ||
            (a is Container container && container.BagOwners.Length != 0 &&
             !container.BagOwners.Contains(p.AccountId)) || (b is Container container2 &&
                                                             container2.BagOwners.Length != 0 &&
                                                             !container2.BagOwners.Contains(p.AccountId))) {
            return false;
        }

        return MathUtils.DistSqr(a.X, a.Y, b.X, b.Y) <= 1f;
    }

    private static bool ValidateSlotSwap(Player player, IContainer conA, IContainer conB, int slotA, int slotB) {
        return conB.AuditItem(conA.Inventory[slotA], slotB) &&
               conA.AuditItem(conB.Inventory[slotB], slotA);
    }

    private static bool ValidateItemSwap(Player player, Entity c, Item item) {
        return c == player || item == null || (!item.Untradable && !player.Client.Account.Admin) ||
               IsSoleContainerOwner(player, (IContainer) c);
    }

    private static bool IsSoleContainerOwner(Player player, IContainer con) {
        int[] owners = null;
        if (con is Container container) {
            owners = container.BagOwners;
        }

        return owners != null && owners.Length == 1 && owners.Contains(player.AccountId);
    }

    private static void DropInUntradableBag(Player player, Item item) {
        var container = new Container(player.Manager, 1283, 60000, dying: true) {
            BagOwners = new int[1] {player.AccountId},
            Inventory = {
                [0] = item
            }
        };
        container.Move(player.X + (float) ((StaticRandom.NextDouble() * 2.0 - 1.0) * 0.5),
            player.Y + (float) ((StaticRandom.NextDouble() * 2.0 - 1.0) * 0.5));
        container.SetDefaultSize(75);
        player.Owner.EnterWorld(container);
    }

    private void ProcessPacket(int len) {
        var ptr = 0;
        ref var spanRef = ref MemoryMarshal.GetReference(ReceiveMem.Span);
        while (ptr < len) {
            var packetLen = ReadUShort(ref ptr, ref spanRef, len);
            var nextPacketPtr = ptr + packetLen - 2;
            var packetId = (C2SPacketId) ReadByte(ref ptr, ref spanRef, nextPacketPtr);
            // Log.Error($"Reading packet {packetId} {nextPacketPtr}");
            switch (packetId) {
                case C2SPacketId.AcceptTrade:
                    ProcessAcceptTrade(ReadBoolArray(ref ptr, ref spanRef, nextPacketPtr),
                        ReadBoolArray(ref ptr, ref spanRef, nextPacketPtr));
                    break;
                case C2SPacketId.AoeAck:
                    ProcessAoeAck(ReadLong(ref ptr, ref spanRef, nextPacketPtr), ReadFloat(ref ptr, ref spanRef, nextPacketPtr),
                        ReadFloat(ref ptr, ref spanRef, nextPacketPtr));
                    break;
                case C2SPacketId.Buy:
                    ProcessBuy(ReadInt(ref ptr, ref spanRef, nextPacketPtr));
                    break;
                case C2SPacketId.CancelTrade:
                    ProcessCancelTrade();
                    break;
                case C2SPacketId.ChangeGuildRank:
                    ProcessChangeGuildRank(ReadString(ref ptr, ref spanRef, nextPacketPtr), ReadInt(ref ptr, ref spanRef, nextPacketPtr));
                    break;
                case C2SPacketId.ChangeTrade:
                    ProcessChangeTrade(ReadBoolArray(ref ptr, ref spanRef, nextPacketPtr));
                    break;
                case C2SPacketId.CreateGuild:
                    ProcessCreateGuild(ReadString(ref ptr, ref spanRef, nextPacketPtr));
                    break;
                case C2SPacketId.EditAccountList:
                    ProcessEditAccountList(ReadInt(ref ptr, ref spanRef, nextPacketPtr), ReadBool(ref ptr, ref spanRef, nextPacketPtr),
                        ReadInt(ref ptr, ref spanRef, nextPacketPtr));
                    break;
                case C2SPacketId.EnemyHit:
                    ProcessEnemyHit(ReadLong(ref ptr, ref spanRef, nextPacketPtr), 
                        ReadByte(ref ptr, ref spanRef, nextPacketPtr), 
                        ReadInt(ref ptr, ref spanRef, nextPacketPtr),
                            ReadBool(ref ptr, ref spanRef, nextPacketPtr));
                    break;
                case C2SPacketId.Escape:
                    ProcessEscape();
                    break;
                case C2SPacketId.GroundDamage:
                    ProcessGroundDamage(ReadLong(ref ptr, ref spanRef, nextPacketPtr), ReadFloat(ref ptr, ref spanRef, nextPacketPtr),
                        ReadFloat(ref ptr, ref spanRef, nextPacketPtr));
                    break;
                case C2SPacketId.GuildInvite:
                    ProcessGuildInvite(ReadString(ref ptr, ref spanRef, nextPacketPtr));
                    break;
                case C2SPacketId.GuildRemove:
                    ProcessGuildRemove(ReadString(ref ptr, ref spanRef, nextPacketPtr));
                    break;
                case C2SPacketId.Hello: {
                    var buildVer = ReadString(ref ptr, ref spanRef, nextPacketPtr);
                    var gameId = ReadInt(ref ptr, ref spanRef, nextPacketPtr);
                    var guid = ReadString(ref ptr, ref spanRef, nextPacketPtr);
                    var pwd = ReadString(ref ptr, ref spanRef, nextPacketPtr);
                    var chrId = ReadShort(ref ptr, ref spanRef, nextPacketPtr);
                    var charType = (ushort) ReadShort(ref ptr, ref spanRef, nextPacketPtr);
                    var skinType = (ushort) ReadShort(ref ptr, ref spanRef, nextPacketPtr);
                    ProcessHello(buildVer, gameId, guid, pwd, chrId, charType, skinType);
                    break;
                }
                case C2SPacketId.MapHello: {
                    var buildVer = ReadString(ref ptr, ref spanRef, nextPacketPtr);
                    var guid = ReadString(ref ptr, ref spanRef, nextPacketPtr);
                    var pwd = ReadString(ref ptr, ref spanRef, nextPacketPtr);
                    var chrId = ReadShort(ref ptr, ref spanRef, nextPacketPtr);
                    var fm = new byte[ReadUShort(ref ptr, ref spanRef, nextPacketPtr)];
                    // todo memcpy
                    for (var i = 0; i < fm.Length; i++)
                        fm[i] = ReadByte(ref ptr, ref spanRef, nextPacketPtr);
                    ProcessMapHello(buildVer, guid, pwd, chrId, fm);
                    break;
                }
                case C2SPacketId.InvDrop:
                    ProcessInvDrop(ReadInt(ref ptr, ref spanRef, nextPacketPtr), ReadByte(ref ptr, ref spanRef, nextPacketPtr));
                    break;
                case C2SPacketId.InvSwap:
                    ProcessInvSwap(ReadLong(ref ptr, ref spanRef, nextPacketPtr),
                        ReadFloat(ref ptr, ref spanRef, nextPacketPtr), ReadFloat(ref ptr, ref spanRef, nextPacketPtr),
                        ReadInt(ref ptr, ref spanRef, nextPacketPtr), ReadByte(ref ptr, ref spanRef, nextPacketPtr),
                        ReadInt(ref ptr, ref spanRef, nextPacketPtr), ReadByte(ref ptr, ref spanRef, nextPacketPtr));
                    break;
                case C2SPacketId.JoinGuild:
                    ProcessJoinGuild(ReadString(ref ptr, ref spanRef, nextPacketPtr));
                    break;
                case C2SPacketId.Move: {
                    var tickId = ReadByte(ref ptr, ref spanRef, nextPacketPtr);
                    var time = ReadLong(ref ptr, ref spanRef, nextPacketPtr);
                    var x = ReadFloat(ref ptr, ref spanRef, nextPacketPtr);
                    var y = ReadFloat(ref ptr, ref spanRef, nextPacketPtr);
                    ProcessMove(tickId, time, x, y, ReadTimedPosArray(ref ptr, ref spanRef, nextPacketPtr));
                    break;
                }
                case C2SPacketId.OtherHit:
                    ProcessOtherHit(ReadLong(ref ptr, ref spanRef, nextPacketPtr), ReadByte(ref ptr, ref spanRef, nextPacketPtr),
                        ReadInt(ref ptr, ref spanRef, nextPacketPtr), ReadInt(ref ptr, ref spanRef, nextPacketPtr));
                    break;
                case C2SPacketId.PlayerHit:
                    ProcessPlayerHit(ReadByte(ref ptr, ref spanRef, nextPacketPtr), ReadInt(ref ptr, ref spanRef, nextPacketPtr));
                    break;
                case C2SPacketId.PlayerShoot:
                    ProcessPlayerShoot(ReadLong(ref ptr, ref spanRef, nextPacketPtr), ReadByte(ref ptr, ref spanRef, nextPacketPtr),
                        ReadUShort(ref ptr, ref spanRef, nextPacketPtr), ReadFloat(ref ptr, ref spanRef, nextPacketPtr),
                        ReadFloat(ref ptr, ref spanRef, nextPacketPtr), ReadFloat(ref ptr, ref spanRef, nextPacketPtr));
                    break;
                case C2SPacketId.PlayerText:
                    ProcessPlayerText(ReadString(ref ptr, ref spanRef, nextPacketPtr));
                    break;
                case C2SPacketId.Pong:
                    ProcessPong(ReadLong(ref ptr, ref spanRef, nextPacketPtr), ReadLong(ref ptr, ref spanRef, nextPacketPtr));
                    break;
                case C2SPacketId.RequestTrade:
                    ProcessRequestTrade(ReadString(ref ptr, ref spanRef, nextPacketPtr));
                    break;
                case C2SPacketId.Reskin:
                    ProcessReskin((ushort) ReadInt(ref ptr, ref spanRef, nextPacketPtr));
                    break;
                case C2SPacketId.ShootAck:
                    ProcessShootAck(ReadLong(ref ptr, ref spanRef, nextPacketPtr));
                    break;
                case C2SPacketId.SquareHit:
                    ProcessSquareHit(ReadLong(ref ptr, ref spanRef, nextPacketPtr), ReadByte(ref ptr, ref spanRef, nextPacketPtr), ReadInt(ref ptr, ref spanRef, nextPacketPtr));
                    break;
                case C2SPacketId.Teleport:
                    ProcessTeleport(ReadInt(ref ptr, ref spanRef, nextPacketPtr));
                    break;
                case C2SPacketId.UpdateAck:
                    ProcessUpdateAck();
                    break;
                case C2SPacketId.UseItem:
                    ProcessUseItem(ReadLong(ref ptr, ref spanRef, nextPacketPtr), 
                        ReadInt(ref ptr, ref spanRef, nextPacketPtr),
                        ReadByte(ref ptr, ref spanRef, nextPacketPtr), 
                        ReadFloat(ref ptr, ref spanRef, nextPacketPtr), 
                        ReadFloat(ref ptr, ref spanRef, nextPacketPtr),
                        ReadByte(ref ptr, ref spanRef, nextPacketPtr));
                    break;
                case C2SPacketId.UsePortal:
                    ProcessUsePortal(ReadInt(ref ptr, ref spanRef, nextPacketPtr));
                    break;
                case C2SPacketId.UseAbility:
                    {
                        var time = ReadLong(ref ptr, ref spanRef, nextPacketPtr);
                        var abilitySlotType = ReadByte(ref ptr, ref spanRef, nextPacketPtr);
                        var data = new byte[ReadUShort(ref ptr, ref spanRef, nextPacketPtr)];
                        // todo memcpy
                        for (var i = 0; i < data.Length; i++)
                            data[i] = ReadByte(ref ptr, ref spanRef, nextPacketPtr);
                        ProcessUseAbility(time, abilitySlotType, data);
                    }
                    break;
                default:
                    Log.Warn($"Unhandled packet '.{packetId}'.");
                    break;
            }

            if (ptr != nextPacketPtr) {
                Log.Warn($"Packet '.{packetId}' has {nextPacketPtr - ptr} bytes left over. This most likely is a mistake");
                ptr = nextPacketPtr;
            }
        }
    }

    private void ProcessAcceptTrade(bool[] myOffer, bool[] yourOffer) {
        if (Player == null || Player.tradeAccepted) {
            return;
        }

        Player.trade = myOffer;
        if (!Player.tradeTarget.trade.SequenceEqual(yourOffer)) {
            return;
        }

        Player.tradeAccepted = true;
        Player.tradeTarget.Client.SendTradeAccepted(Player.tradeTarget.trade, Player.trade);
        if (!Player.tradeAccepted || !Player.tradeTarget.tradeAccepted) {
            return;
        }

        if (Player.Client.Account.Admin != Player.tradeTarget.Client.Account.Admin) {
            Player.tradeTarget.CancelTrade();
            Player.CancelTrade();
            return;
        }

        var failedMsg = "Error while trading. Trade unsuccessful.";
        var msg = "Trade Successful!";
        var thisItems = new List<Item>();
        var targetItems = new List<Item>();
        var tradeTarget = Player.tradeTarget;
        if (tradeTarget == null || Player.Owner == null || tradeTarget.Owner == null ||
            Player.Owner != tradeTarget.Owner) {
            SendTradeDone(1, failedMsg);
            tradeTarget?.Client.SendTradeDone(1, failedMsg);
            Player.ResetTrade();
        }
        else {
            if (!Player.tradeAccepted || !tradeTarget.tradeAccepted) {
                return;
            }

            var pInvTrans = Player.Inventory.CreateTransaction();
            var tInvTrans = tradeTarget.Inventory.CreateTransaction();
            for (var l = 4; l < Player.trade.Length; l++) {
                if (Player.trade[l]) {
                    thisItems.Add(Player.Inventory[l]);
                    pInvTrans[l] = null;
                }
            }

            for (var k = 4; k < tradeTarget.trade.Length; k++) {
                if (tradeTarget.trade[k]) {
                    targetItems.Add(tradeTarget.Inventory[k]);
                    tInvTrans[k] = null;
                }
            }

            for (var j = 0; j < 22; j++) {
                for (var m = 0; m < thisItems.Count; m++) {
                    if ((tradeTarget.SlotTypes[j] == 0 && tInvTrans[j] == null) || (thisItems[m] != null &&
                            ItemUtils.SlotsMatching(tradeTarget.SlotTypes[j], thisItems[m].SlotType) &&
                            tInvTrans[j] == null)) {
                        tInvTrans[j] = thisItems[m];
                        thisItems.Remove(thisItems[m]);
                        break;
                    }
                }
            }

            for (var i = 0; i < 22; i++) {
                for (var n = 0; n < targetItems.Count; n++) {
                    if ((Player.SlotTypes[i] == 0 && pInvTrans[i] == null) || (targetItems[n] != null &&
                                                                               ItemUtils.SlotsMatching(
                                                                                   Player.SlotTypes[i],
                                                                                   targetItems[n].SlotType) &&
                                                                               pInvTrans[i] == null)) {
                        pInvTrans[i] = targetItems[n];
                        targetItems.Remove(targetItems[n]);
                        break;
                    }
                }
            }

            if (!Inventory.Execute(pInvTrans, tInvTrans)) {
                SendTradeDone(1, failedMsg);
                tradeTarget?.Client.SendTradeDone(1, failedMsg);
                Player.ResetTrade();
                return;
            }

            if (thisItems.Count > 0 || targetItems.Count > 0) {
                msg = "An error occured while trading! Some items were lost!";
            }

            SendTradeDone(1, msg);
            tradeTarget?.Client.SendTradeDone(1, msg);
            Player.ResetTrade();
        }
    }

    private void ProcessAoeAck(long time, float x, float y) { }

    private void ProcessBuy(int id) {
        (Player?.Owner?.GetEntity(id) as SellableObject)?.Buy(Player);
    }

    private void ProcessCancelTrade() {
        Player?.CancelTrade();
    }

    private void ProcessChangeGuildRank(string name, int rank) {
        if (Player == null) {
            return;
        }

        var targetId = Manager.Database.ResolveId(name);
        if (targetId == 0) {
            Player.SendError("A player with that name does not exist.");
            return;
        }

        var targetCli = Manager.Clients.Keys.SingleOrDefault(c => c.Account.AccountId == targetId);
        var targetAcnt =
            ((targetCli != null) ? targetCli.Account : Manager.Database.GetAccount(targetId));
        if (Account.GuildId <= 0 || Account.GuildRank < 20 ||
            Account.GuildRank <= targetAcnt.GuildRank || Account.GuildRank < rank || rank == 40 ||
            Account.GuildId != targetAcnt.GuildId) {
            Player.SendError("No permission");
            return;
        }

        if (1 == 0) { }

        var text = rank switch {
            0 => "Initiate",
            10 => "Member",
            20 => "Officer",
            30 => "Leader",
            40 => "Founder",
            _ => "",
        };
        if (1 == 0) { }

        var targetRank = targetAcnt.GuildRank;
        if (targetRank == rank) {
            Player.SendError("Player is already a " + text);
            return;
        }

        if (!Manager.Database.ChangeGuildRank(targetAcnt, rank)) {
            Player.SendError("Failed to change rank.");
            return;
        }

        if (targetCli != null) {
            targetCli.Player.GuildRank = (sbyte) rank;
        }

        if (targetRank < rank) {
            Manager.Chat.Guild(Player, targetAcnt.Name + " has been promoted to " + text + ".", announce: true);
        }
        else {
            Manager.Chat.Guild(Player, targetAcnt.Name + " has been demoted to " + text + ".", announce: true);
        }
    }

    private void ProcessChangeTrade(bool[] offer) {
        if (Player?.tradeTarget == null) {
            return;
        }

        for (var i = 0; i < offer.Length; i++) {
            if (offer[i] && Player.Inventory[i].Untradable) {
                Player.SendError("You can't trade Untradable items.");
                return;
            }
        }

        Player.tradeAccepted = false;
        Player.tradeTarget.tradeAccepted = false;
        Player.trade = offer;
        Player.tradeTarget.Client.SendTradeChanged(offer);
    }
    
    private void ProcessCreateGuild(string guildName) {
        if (Player == null) {
            return;
        }

        if (Account.GuildId > 0) {
            SendGuildResult(success: false, "Guild Creation Error: Already in a guild");
            return;
        }

        var guildRes = Manager.Database.CreateGuild(guildName, out var createdGuild);
        if ((int) guildRes > 0) {
            SendGuildResult(success: false,
                "Guild Creation Error: " + guildRes);
            return;
        }

        var addResult = Manager.Database.AddGuildMember(createdGuild, Account, true);
        if ((int) addResult > 0) {
            SendGuildResult(success: false,
                "Guild Creation Error: " + addResult);
            return;
        }

        Player.Guild = createdGuild.Name;
        Player.GuildRank = 40;
        SendGuildResult(success: true, "Success!");
    }

    private void ProcessEditAccountList(int action, bool add, int id) {
        if (Player == null) {
            return;
        }

        var targetPlayer = Player.Owner.GetEntity(id) as Player;
        if (targetPlayer?.Client.Account == null) {
            Player.SendError("Player not found.");
            return;
        }

        switch (action) {
            case 0:
                Manager.Database.LockAccount(Account, targetPlayer.Client.Account, add);
                break;
            case 1:
                Manager.Database.IgnoreAccount(Account, targetPlayer.Client.Account, add);
                break;
        }
    }

    private void ProcessEnemyHit(long time, byte bulletId, int targetId, bool kill) {
        if (Player?.Owner == null) 
            return;
        
        if (Player.Owner.Enemies.TryGetValue(targetId, out var en))
            Player._projectiles[bulletId].ForceHit(en, Manager.Logic.WorldTime);
        else if (Player.Owner.StaticObjects.TryGetValue(targetId, out var so) && so.ObjectDesc.Enemy)
            Player._projectiles[bulletId].ForceHit(so, Manager.Logic.WorldTime);
    }

    private void ProcessEscape() {
        if (Player?.Owner != null) {
            Reconnect("the Retrieve", -2);
        }
    }

    private void ProcessGroundDamage(long time, float x, float y) {
        if (Player?.Owner != null)
            Player.ForceGroundHit(x, y, time);
    }

    private void ProcessGuildInvite(string name) {
        if (Player == null) {
            return;
        }

        if (Account.GuildRank < 20) {
            Player.SendError("Insufficient privileges.");
            return;
        }

        foreach (var client in Manager.Clients.Keys) {
            if (client.Player == null || client.Account == null || !client.Account.Name.Equals(name)) {
                continue;
            }

            if (client.Account.GuildId > 0) {
                Player.SendError("Player is already in a guild.");
                return;
            }

            client.Player.GuildInvite = Account.GuildId;
            client.SendInvitedToGuild(Player.Guild, Account.Name);
            return;
        }

        Player.SendError("Could not find the player to invite.");
    }

    private void ProcessGuildRemove(string name) {
        if (Player == null) {
            return;
        }

        if (Account.Name.Equals(name)) {
            Manager.Chat.Guild(Player, Player.Name + " has left the guild.", announce: true);
            if (!Manager.Database.RemoveFromGuild(Account)) {
                Player.SendError("Guild not found.");
                return;
            }

            Player.Guild = "";
            Player.GuildRank = 0;
            return;
        }

        var targetAccId = Manager.Database.ResolveId(name);
        if (targetAccId == 0) {
            Player.SendError("Player not found");
            return;
        }

        var targetClient = (from client in Manager.Clients.Keys
            where client.Account != null
            where client.Account.AccountId == targetAccId
            select client).FirstOrDefault();
        if (targetClient != null) {
            if (Account.GuildRank >= 20 && Account.GuildId == targetClient.Account.GuildId &&
                Account.GuildRank > targetClient.Account.GuildRank) {
                if (!Manager.Database.RemoveFromGuild(targetClient.Account)) {
                    Player.SendError("Guild not found.");
                    return;
                }

                targetClient.Player.Guild = "";
                targetClient.Player.GuildRank = 0;
                Manager.Chat.Guild(Player,
                    targetClient.Player.Name + " has been kicked from the guild by " + Player.Name, announce: true);
                targetClient.Player.SendInfo("You have been kicked from the guild.");
            }
            else {
                Player.SendError("Can't remove member. Insufficient privileges.");
            }

            return;
        }

        var targetAccount = Manager.Database.GetAccount(targetAccId);
        if (Account.GuildRank >= 20 && Account.GuildId == targetAccount.GuildId &&
            Account.GuildRank > targetAccount.GuildRank) {
            if (!Manager.Database.RemoveFromGuild(targetAccount)) {
                Player.SendError("Guild not found.");
                return;
            }

            Manager.Chat.Guild(Player, targetAccount.Name + " has been kicked from the guild by " + Player.Name,
                announce: true);
            Manager.Chat.SendInfo(targetAccId, "You have been kicked from the guild.");
        }
        else {
            Player.SendError("Can't remove member. Insufficient privileges.");
        }
    }

    private void ProcessHello(string buildVer, int gameId, string guid, string pwd, int charId,
        ushort charType, ushort skinType) {
        var version = Manager.Config.serverSettings.version;
        if (!version.Equals(buildVer)) {
            SendFailure(version, FailureType.ClientUpdateNeeded);
            return;
        }

        var val = Manager.Database.Verify(guid, pwd, out var acc);
        if (val is LoginStatus.InvalidCredentials or LoginStatus.AccountNotExists) {
            SendFailure("Failed to login: Invalid credentials");
            return;
        }

        if (acc.Banned || Manager.Database.IsIpBanned(IP)) {
            SendFailure("Failed to login: Account banned");
            Log.Info($"Banned user <{acc.Name}> (ip: {IP}) tried to log in.");
            return;
        }

        if (!acc.Admin && Manager.Config.serverInfo.adminOnly) {
            SendFailure("Failed to login: Insufficient permissions");
            return;
        }

        Manager.Database.LogAccountByIp(IP, acc.AccountId);
        acc.IP = IP;
        acc.FlushAsync();
        Account = acc;
        if (charType != 0) {
            var status = Manager.Database.CreateCharacter(Manager.Resources.GameData, acc, charType, skinType,
                out var character);
            switch (status) {
                case CreateStatus.ReachCharLimit:
                    SendFailure("Too many characters");
                    return;
                case CreateStatus.SkinUnavailable:
                    SendFailure("Skin unavailable");
                    return;
                case CreateStatus.Locked:
                    SendFailure("Class locked");
                    return;
            }

            Character = character;
            Player = new Player(this);
            charId = character.CharId;
        }

        ConnectManager.Connect(this, gameId, charId);
    }

    private void ProcessMapHello(string buildVer, string guid, string pwd, short charId, byte[] fm) {
        var version = Manager.Config.serverSettings.version;
        if (!version.Equals(buildVer)) {
            SendFailure(version, FailureType.ClientUpdateNeeded);
            return;
        }

        var val = Manager.Database.Verify(guid, pwd, out var acc);
        if (val is LoginStatus.InvalidCredentials or LoginStatus.AccountNotExists) {
            SendFailure("Failed to login: Invalid credentials");
            return;
        }

        if (acc.Banned || Manager.Database.IsIpBanned(IP)) {
            SendFailure("Failed to login: Account banned");
            Log.Info($"Banned user <{acc.Name}> (ip: {IP}) tried to log in.");
            return;
        }

        if (!acc.Admin && Manager.Config.serverInfo.adminOnly) {
            SendFailure("Failed to login: Insufficient permissions");
            return;
        }

        Manager.Database.LogAccountByIp(IP, acc.AccountId);
        acc.IP = IP;
        acc.FlushAsync();
        Account = acc;

        ConnectManager.MapConnect(this, charId, fm);
    }

    private void ProcessInvDrop(int objId, byte slotId) {
        if (Player?.Owner == null || Player.tradeTarget != null) {
            return;
        }

        IContainer con;
        if (objId != Player.Id) {
            if (Player.Owner.GetEntity(objId) is Player) {
                SendInvResult(1);
                return;
            }

            con = Player.Owner.GetEntity(objId) as IContainer;
        }
        else {
            con = Player;
        }

        if (con?.Inventory[slotId] == null) {
            SendInvResult(1);
            return;
        }

        var dropItem = con.Inventory[slotId];
        con.Inventory[slotId] = null;
        Container container;
        if (dropItem.Untradable || Player.Client.Account.Admin) {
            var container2 = new Container(Player.Manager, 1287, 60000, dying: true);
            container2.BagOwners = new int[1] {Player.AccountId};
            container = container2;
        }
        else {
            container = new Container(Player.Manager, 1280, 60000, dying: true);
        }

        container.Inventory[0] = dropItem;
        container.Move(Player.X + (float) ((ClientRandom.NextDouble() * 2.0 - 1.0) * 0.5),
            Player.Y + (float) ((ClientRandom.NextDouble() * 2.0 - 1.0) * 0.5));
        container.SetDefaultSize(75);
        Player.Owner.EnterWorld(container);
        SendInvResult(0);
    }

    private void ProcessInvSwap(long time, float x, float y, int objId1, byte slotId1, int objId2, byte slotId2) {
        if (Player?.Owner == null) {
            return;
        }

        var a = Player.Owner.GetEntity(objId1);
        var b = Player.Owner.GetEntity(objId2);
        if (!ValidateEntities(Player, a, b) || Player.tradeTarget != null) {
            a.ForceUpdate(slotId1);
            b.ForceUpdate(slotId2);
            SendInvResult(1);
            return;
        }

        var conA = (IContainer) a;
        var conB = (IContainer) b;
        if (!ValidateSlotSwap(Player, conA, conB, slotId1, slotId2)) {
            a.ForceUpdate(slotId1);
            b.ForceUpdate(slotId2);
            SendInvResult(1);
            return;
        }

        var queue = new Queue<Action>();
        var conATrans = conA.Inventory.CreateTransaction();
        var conBTrans = conB.Inventory.CreateTransaction();
        var itemA = conATrans[slotId1];
        var itemB = conBTrans[slotId2];
        conBTrans[slotId2] = itemA;
        conATrans[slotId1] = itemB;
        if (!ValidateItemSwap(Player, a, itemB)) {
            queue.Enqueue(delegate { DropInUntradableBag(Player, itemB); });
            conATrans[slotId1] = null;
        }

        if (!ValidateItemSwap(Player, b, itemA)) {
            queue.Enqueue(delegate { DropInUntradableBag(Player, itemA); });
            conBTrans[slotId2] = null;
        }

        if (Inventory.Execute(conATrans, conBTrans)) {
            while (queue.Count > 0) {
                queue.Dequeue()();
            }

            SendInvResult(0);
        }
        else {
            a.ForceUpdate(slotId1);
            b.ForceUpdate(slotId2);
            SendInvResult(1);
        }
    }

    public void ProcessJoinGuild(string guildName) {
        if (Player == null) {
            return;
        }

        if (!Player.GuildInvite.HasValue) {
            Player.SendError("You have not been invited to a guild.");
            return;
        }

        var guild = Manager.Database.GetGuild(Player.GuildInvite.Value);
        if (guild == null) {
            Player.SendError("Internal server error.");
            return;
        }

        if (!guild.Name.Equals(guildName, StringComparison.InvariantCultureIgnoreCase)) {
            Player.SendError("You have not been invited to join " + guildName + ".");
            return;
        }

        var guildResult = Manager.Database.AddGuildMember(guild, Account);
        if ((int) guildResult > 0) {
            Player.SendError("Could not join guild. (" + guildResult + ")");
            return;
        }

        Player.Guild = guild.Name;
        Player.GuildRank = 0;
        Manager.Chat.Guild(Player, Player.Name + " has joined the guild!", announce: true);
    }

    private void ProcessMove(byte tickId, long time, float x, float y, TimedPosition[] records) {
        if (Player?.Owner == null || x < 0f || x >= Player.Owner.Map.Width || y < 0f ||
            y >= Player.Owner.Map.Height)
            return;
        Player.MoveReceived(Manager.Logic.WorldTime, tickId, time);
        // ReSharper disable once CompareOfFloatsByEqualityOperator
        if (x != Player.X || y != Player.Y)
            Player.Move(x, y);
    }

    private void ProcessOtherHit(long time, byte bulletId, int ownerId, int targetId) { }

    private void ProcessPlayerHit(byte bulletId, int objId) {
        if (Player?.Owner != null && Player.Owner.Enemies.TryGetValue(objId, out var enemy)) {
            enemy._projectiles[bulletId].ForceHit(Player, Manager.Logic.WorldTime);
        }
    }

    private void ProcessPlayerShoot(long time, byte bulletId, ushort objType, float x, float y, float angle) {
        if (!Manager.Resources.GameData.Items.TryGetValue(objType, out var item) || item == Player.Inventory[1]) 
            return;
        
        var prjDesc = item.Projectiles[0];
        var prj = Player.PlayerShootProjectile(bulletId, prjDesc, item.ObjectType, x, y);
        Player.Owner.EnterWorld(prj);
            
        foreach (var plr in Player.Owner.Players.Values)
            if (plr.Id != Player.Id && MathUtils.DistSqr(plr.X, plr.Y, Player.X, Player.Y) < 16 * 16)
                plr.Client.SendAllyShoot(prj.BulletId, Player.Id, prj.Container, angle);
    }

    private void ProcessPlayerText(string text) {
        if (Player?.Owner == null || text.Length > 512)
            return;

        var manager = Player.Manager;
        if (text[0] == '/') {
            manager.Commands.Execute(Player, Manager.Logic.WorldTime, text);
            return;
        }

        if (Player.Muted) {
            Player.SendError("Muted. You can not talk at this time.");
            return;
        }

        manager.Chat.Say(Player, text);
    }

    private void ProcessPong(long serial, long pongTime) {
        Player?.Pong(Manager.Logic.WorldTime, pongTime, serial);
    }

    private void ProcessRequestTrade(string name) {
        Player?.RequestTrade(name);
    }

    private void ProcessReskin(ushort skinId) {
        if (Player == null) {
            return;
        }

        var gameData = Manager.Resources.GameData;
        Account.Reload("skins");
        var ownedSkins = Account.Skins;
        var currentClass = Player.ObjectType;
        var skinData = gameData.Skins;
        var skinSize = 100;
        if (skinId != 0) {
            skinData.TryGetValue(skinId, out var skinDesc);
            if (skinDesc == null) {
                Player.SendError("Unknown skin type.");
                return;
            }

            if (!ownedSkins.Contains(skinId)) {
                Player.SendError("Skin not owned.");
                return;
            }

            if (skinDesc.PlayerClassType != currentClass) {
                Player.SendError("Skin is for different class.");
                return;
            }

            skinSize = skinDesc.Size;
        }

        Player.SetDefaultSkin(skinId);
        Player.SetDefaultSize((ushort) skinSize);
    }

    private void ProcessShootAck(long time) { }

    private void ProcessSquareHit(long time, byte bulletId, int objId) { }

    private void ProcessTeleport(int objId) {
        if (Player?.Owner != null) {
            Player.Teleport(Manager.Logic.WorldTime, objId);
        }
    }

    private void ProcessUpdateAck() {
        Player.UpdateAckReceived();
    }

    private void ProcessUseItem(long time, int objId, byte slotId, float x, float y, byte useType) {
        if (Player?.Owner != null) {
            Player.UseItem(objId, slotId, x, y);
        }
    }

    private void ProcessUseAbility(long time, byte abilitySlotType, byte[] data)
    {
        if (Player?.Owner != null)
        {
            var abilityType = (AbilitySlotType)abilitySlotType;
            var success = Player.TryUseAbility(time, abilityType, data);
            if (!success)
                Disconnect($"[{Player.Name}] Failed to use ability: {abilityType} for: {Player.ObjectDesc.ObjectId}");
        }
    }

    private void ProcessUsePortal(int objId) {
        var entity = Player?.Owner?.GetEntity(objId);
        switch (entity) {
            case null:
                return;
            case GuildHallPortal guildHallPortal when string.IsNullOrEmpty(Player.Guild):
                Player.SendError("You are not in a guild.");
                break;
            /*ProtoWorld proto = Player.Manager.Resources.Worlds.Item("GuildHall");
                var world2 = Player.Manager.GetWorld(proto.id);
                Player.Reconnect(world2);*/
            case GuildHallPortal guildHallPortal when guildHallPortal.ObjectType != 1839:
                Player.SendInfo("Portal not implemented.");
                return;
        }

        if (entity.ObjectType == 0x0707) // stash portal
        {
            // make a new stash every time????
            Player.Reconnect(Player.Manager.CreateNewStash(Player.Client));
            return;
        }

        if (entity is not Portal portal || !portal.Usable)
            return;
        
        lock (portal.CreateWorldLock) {
            var world = portal.WorldInstance;
            if (world != null) {
                Player.Reconnect(world);
                return;
            }

            if (portal.CreateWorldTask == null || portal.CreateWorldTask.IsCompleted) {
                portal.CreateWorldTask = Task.Factory.StartNew(delegate { portal.CreateWorld(Player); }).ContinueWith(
                    delegate(Task e) {
                        if (e.Exception?.InnerException != null) {
                            Log.Error(e.Exception!.InnerException!.ToString());
                        }
                    }, TaskContinuationOptions.OnlyOnFaulted);
            }

            portal.WorldInstanceSet += Player.Reconnect;
        }
    }

    public void Disconnect(string reason = "") {
        SendFailure(reason, FailureType.MessageWithDisconnect, false);

        if (reason != "")
            Log.Info("Disconnecting client ({0}) @ {1}... {2}",
                Account?.Name ?? "[unconnected]", IP, reason);

        if (Account != null) {
            try {
                if (Character == null || Player == null) {
                    Manager.Database.ReleaseLock(Account);
                    return;
                }

                Player.SaveToCharacter();
                Player?.Owner?.LeaveWorld(Player); // this can cause a error if owner is null so im gunna null check it
                Account.RefreshLastSeen();
                Account.FlushAsync();
                Manager.Database.SaveCharacter(Account, Character, true)
                    .ContinueWith(delegate { Manager.Database.ReleaseLock(Account); });
            }
            catch (Exception e) {
                Log.Error(e.Message + "\n" + e.StackTrace);
            }
        }

        Manager.Disconnect(this);
        _server.Disconnect(this);
    }

    public bool KeepAlive(RealmTime time, int position, int count) {
        if (_pingTime == -1) {
            _pingTime = time.TotalElapsedUs - 3000 * 1000;
            _pongTime = time.TotalElapsedUs;
        }

        if (time.TotalElapsedUs - _pongTime > 15000 * 1000) {
            Disconnect("Queue connection timeout. (KeepAlive)");
            return false;
        }

        if (time.TotalElapsedUs - _pingTime < 3000 * 1000) {
            return true;
        }

        _pingTime = time.TotalElapsedUs;
        _serial = (int) _pingTime;
        return true;
    }
}
