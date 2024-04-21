using System.Collections.Concurrent;
using Shared;
using Shared.resources;
using GameServer.logic;
using GameServer.realm.commands;
using GameServer.realm.setpieces;
using GameServer.realm.worlds;
using GameServer.realm.worlds.logic;
using NLog;

namespace GameServer.realm; 

public struct RealmTime
{
    public long TickCount;
    public long TotalElapsedUs;
    public long TickDelta;
    public long ElapsedUsDelta;
}

public class RealmManager
{
    private static readonly Logger Log = LogManager.GetCurrentClassLogger();

    private readonly bool _initialized;
    public string InstanceId { get; private set; }
    public bool Terminating { get; private set; }

    public Resources Resources { get; private set; }
    public Database Database { get; private set; }
    public ServerConfig Config { get; private set; }
    public int TPS { get; private set; }

    public ConnectManager ConMan { get; private set; }
    public BehaviorDb Behaviors { get; private set; }
    public ISManager InterServer { get; private set; }
    public ISControl ISControl { get; private set; }
    public ChatManager Chat { get; private set; }
    public CommandManager Commands { get; private set; }
    public PortalMonitor Monitor { get; private set; }
    public DbEvents DbEvents { get; private set; }

    private Thread _network;
    private Thread _logic;
    public LogicTicker Logic { get; private set; }

    public readonly ConcurrentDictionary<int, World> Worlds = new();

    public readonly ConcurrentDictionary<Client, PlayerInfo> Clients =
        new();

    private int _nextWorldId = 0;
    private int _nextClientId = 0;

    public RealmManager(Resources resources, Database db, ServerConfig config)
    {
        Log.Info("Initializing Realm Manager...");

        InstanceId = Guid.NewGuid().ToString();
        Database = db;
        Resources = resources;
        Config = config;
        Config.serverInfo.instanceId = InstanceId;
        TPS = config.serverSettings.tps;

        // all these deal with db pub/sub... probably should put more thought into their structure... 
        InterServer = new ISManager(Database, config);
        InterServer.AddHandler<RebootBehaviorMsg>(Channel.RebootBehaviors, HandleRebootBehaviors);
        ISControl = new ISControl(this);
        Chat = new ChatManager(this);
        DbEvents = new DbEvents(this);

        // basic server necessities
        ConMan = new ConnectManager(this);
        Behaviors = new BehaviorDb(this);
        Commands = new CommandManager(this);

        InitializeGlobalWorlds();

        // add portal monitor to nexus and initialize worlds
        if (Worlds.ContainsKey(World.Retrieve))
            Monitor = new PortalMonitor(this, Worlds[World.Retrieve]);
        foreach (var world in Worlds.Values)
            OnWorldAdded(world);

        _initialized = true;

        Log.Info("Realm Manager initialized.");
    }
        
    private void HandleRebootBehaviors(object sender, InterServerEventArgs<RebootBehaviorMsg> e) {
        BehaviorDb.InitDb.InitXmlBehaviors();
    }

    private void InitializeGlobalWorlds()
    {
        // load world data
        foreach (var wData in Resources.Worlds.Data.Values)
            if (wData.id < 0)
                AddWorld(wData);
    }

    public void Run()
    {
        Log.Info("Starting Realm Manager...");

        // start server logic management
        Logic = new LogicTicker(this);
        var logic = new Task(() => Logic.TickLoop(), TaskCreationOptions.LongRunning);
        logic.ContinueWith(Program.Stop, TaskContinuationOptions.OnlyOnFaulted);
        logic.Start();

        Log.Info("Realm Manager started.");
    }

    public void Stop()
    {
        Log.Info("Stopping Realm Manager...");

        Terminating = true;
        InterServer.Dispose();

        Log.Info("Realm Manager stopped.");
    }

    public bool TryConnect(Client client)
    {
        if (client?.Account == null)
            return false;

        if (Clients.Keys.Contains(client))
            Disconnect(client);

        //client.Id = Interlocked.Increment(ref _nextClientId);
        var plrInfo = new PlayerInfo {
            AccountId = client.Account.AccountId,
            GuildId = client.Account.GuildId,
            Name = client.Account.Name,
            WorldInstance = -1
        };
        Clients[client] = plrInfo;

        // recalculate usage statistics
        Config.serverInfo.players = ConMan.GetPlayerCount();
        Config.serverInfo.maxPlayers = Config.serverSettings.maxPlayers;
        Config.serverInfo.playerList.Add(plrInfo);
        return true;
    }

    public void Disconnect(Client client)
    {
        var player = client.Player;
        player?.Owner?.LeaveWorld(player);

        PlayerInfo plrInfo;
        Clients.TryRemove(client, out plrInfo);

        // recalculate usage statistics
        Config.serverInfo.players = ConMan.GetPlayerCount();
        Config.serverInfo.maxPlayers = Config.serverSettings.maxPlayers;
        Config.serverInfo.playerList.Remove(plrInfo);
    }

    public Stash CreateNewStash(Client client)
    {
        var proto = Resources.Worlds.Data["Stash"];
        var id = Interlocked.Increment(ref _nextWorldId);
        var stash = new Stash(proto, client);
        AddWorld(id, stash);
        return stash;
    }
    
    private void AddWorld(string name, bool actAsHub = false)
    {
        AddWorld(Resources.Worlds.Data[name], actAsHub);
    }

    private void AddWorld(ProtoWorld proto, bool actAsHub = false)
    {
        int id;
        if (actAsHub)
        {
            id = World.Retrieve;
        }
        else
        {
            id = (proto.id < 0)
                ? proto.id
                : Interlocked.Increment(ref _nextWorldId);
        }

        var world = new World(proto);
        if (world != null)
        {
            AddWorld(id, world);
            return;
        }

        AddWorld(id, new World(proto));
    }

    private void AddWorld(int id, World world)
    {
        if (world.Manager != null)
            throw new InvalidOperationException("World already added.");
        world.Id = id;
        Worlds[id] = world;
        if (_initialized)
            OnWorldAdded(world);
    }

    public World AddWorld(World world)
    {
        if (world.Manager != null)
            throw new InvalidOperationException("World already added.");
        world.Id = Interlocked.Increment(ref _nextWorldId);
        Worlds[world.Id] = world;
        if (_initialized)
            OnWorldAdded(world);
        return world;
    }

    public World GetWorld(int id) {
        return !Worlds.TryGetValue(id, out var ret) ? null : ret.Id == 0 ? null : ret;
    }

    public bool RemoveWorld(World world)
    {
        if (world.Manager == null)
            throw new InvalidOperationException("World is not added.");
        if (Worlds.TryRemove(world.Id, out world))
        {
            OnWorldRemoved(world);
            return true;
        }
        else
            return false;
    }

    private void OnWorldAdded(World world)
    {
        world.Manager = this;
        Log.Info("World {0}({1}) added. {2} Worlds existing.", world.Id, world.Name, Worlds.Count);
    }

    private void OnWorldRemoved(World world)
    {
        //world.Manager = null;
        Monitor.RemovePortal(world.Id);
        Log.Info("World {0}({1}) removed.", world.Id, world.Name);
    }

    public World GetGameWorld(Client client)
    {
        return Worlds[World.Retrieve];
    }
}