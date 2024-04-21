using Shared;
using GameServer.realm.entities.player;
using GameServer.realm.worlds;
using Shared.resources;
using StackExchange.Redis;

namespace GameServer.realm; 

public class ConnectManager {
    private RealmManager _manager;

    public ConnectManager(RealmManager manager) {
        _manager = manager;
    }

    public int GetPlayerCount() {
        return _manager.Clients.Count;
    }

    public static void Reconnect(Client client, int gameId) {
        var player = client.Player;
        var currentWorld = client.Player.Owner;

        var world = client.Manager.GetWorld(gameId);
        if (world == null || world.Deleted) {
            client.SendText("*Error*", 0, 0, "", "World does not exist.");
            world = client.Manager.GetWorld(World.Retrieve);
        }

        if (world.IsLimbo) {
            world = world.GetInstance();
        }

        if (!world.AllowedAccess(client)) {
            client.SendText("*Error*", 0, 0, "", "Access denied");
            if (gameId == World.Retrieve) {
                client.Disconnect();
                return;
            }

            world = client.Manager.GetWorld(World.Retrieve);
        }

        var mapSize = Math.Max(world.Map.Width, world.Map.Height);
        client.SendMapInfo(mapSize, mapSize, world.Name, world.BgLightColor, world.BgLightIntensity,
            world.AllowTeleport, world.DayLightIntensity, world.NightLightIntensity);
        client.SendAccountList(0, client.Account.LockList);
        client.SendAccountList(1, client.Account.IgnoreList);
        if (client.Character != null) {
            if (client.Character.Dead) {
                client.SendFailure("Character is dead");
                return;
            }

            currentWorld?.LeaveWorld(player);
            player.DisposeUpdate();

            var objectId = world.EnterWorld(player, true);
            client.SendCreateSuccess(objectId, client.Character.CharId);
        }
        else {
            client.SendFailure("Failed to load character");
        }
    }
        
    public static void MapConnect(Client client, int charId, byte[] eclipseMap) {
        // todo maybe don't allow doctor kischak to save billions of maps on server?
        var mapFolder = $"{client.Manager.Config.serverSettings.logFolder}/maps";
        if (!Directory.Exists(mapFolder))
            Directory.CreateDirectory(mapFolder);
        File.WriteAllBytes($"{mapFolder}/{client.Account.Name}_{DateTime.Now.Ticks}.em", eclipseMap);
            
        if (!client.Manager.Database.AcquireLock(client.Account)) {
            var otherClients = client.Manager.Clients.Keys.Where((Client c) =>
                c == client || (c.Account != null && c.Account.AccountId == client.Account.AccountId));
            foreach (var otherClient in otherClients) {
                otherClient.Disconnect();
            }

            if (!client.Manager.Database.AcquireLock(client.Account)) {
                client.SendFailure("Account locked (" +
                                   client.Manager.Database.GetLockTime(client.Account)?.ToString("%s") +
                                   " seconds until timeout)");
                return;
            }
        }

        client.Account.Reload();
        if (!client.Manager.TryConnect(client)) {
            client.SendFailure("Failed to connect");
            return;
        }

        var world = client.Manager.AddWorld(new World(new ProtoWorld {
            name = "Test World",
            sbName = "Test World",
            id = 0,
            setpiece = false,
            showDisplays = false,
            bgLightColor = 0,
            bgLightIntensity = 0.2f,
            blocking = 0,
            isLimbo = false,
            persist = false,
            portals = Array.Empty<int>(),
            restrictTp = false,
            map = "",
            mapData = eclipseMap,
            // to-do: add test music
            music = new[] { "Test" }
        }));
        if (world == null || world.Deleted) {
            client.SendText("*Error*", 0, 0, "", "World does not exist.");
            world = client.Manager.GetWorld(World.Retrieve);
        }
            
        if (!world.AllowedAccess(client)) {
            client.SendText("*Error*", 0, 0, "", "Access denied");
            world = client.Manager.GetWorld(World.Retrieve);
        }

        client.Account.RefreshLastSeen();
        client.Account.FlushAsync();
        var mapSize = Math.Max(world.Map.Width, world.Map.Height);
        client.SendMapInfo(mapSize, mapSize, world.Name, world.BgLightColor, world.BgLightIntensity,
            world.AllowTeleport, world.DayLightIntensity, world.NightLightIntensity);
        client.SendAccountList(0, client.Account.LockList);
        client.SendAccountList(1, client.Account.IgnoreList);
        client.Character = client.Manager.Database.LoadCharacter(client.Account, charId);
        if (client.Character != null) {
            if (client.Character.Dead) {
                client.SendFailure("Character is dead");
                return;
            }

            if (client.Player?.Owner == null)
                client.Player = new Player(client);
            client.SendCreateSuccess(client.Manager.Worlds[world.Id].EnterWorld(client.Player),
                client.Character.CharId);
            client.Manager.Clients[client].WorldInstance = client.Player.Owner.Id;
            client.Manager.Clients[client].WorldName = client.Player.Owner.Name;
        }
        else {
            client.SendFailure("Failed to load character");
        }
    }

    public static void Connect(Client client, int gameId, int charId) {
        if (gameId != -6) {
            gameId = -2;
        }

        if (!client.Manager.Database.AcquireLock(client.Account)) {
            var otherClients = client.Manager.Clients.Keys.Where((Client c) =>
                c == client || (c.Account != null && c.Account.AccountId == client.Account.AccountId));
            foreach (var otherClient in otherClients) {
                otherClient.Disconnect();
            }

            if (!client.Manager.Database.AcquireLock(client.Account)) {
                client.SendFailure("Account locked (" +
                                   client.Manager.Database.GetLockTime(client.Account)?.ToString("%s") +
                                   " seconds until timeout)");
                return;
            }
        }

        client.Account.Reload();
        if (!client.Manager.TryConnect(client)) {
            client.SendFailure("Failed to connect");
            return;
        }

        var world = client.Manager.GetWorld(gameId);
        if (world == null || world.Deleted) {
            client.SendText("*Error*", 0, 0, "", "World does not exist.");
            world = client.Manager.GetWorld(-2);
        }

        if (world.IsLimbo) {
            world = world.GetInstance();
        }

        if (!world.AllowedAccess(client)) {
            client.SendText("*Error*", 0, 0, "", "Access denied");
            if (gameId == -2) {
                client.Disconnect();
                return;
            }

            world = client.Manager.GetWorld(-2);
        }

        client.Account.RefreshLastSeen();
        client.Account.FlushAsync();
        var mapSize = Math.Max(world.Map.Width, world.Map.Height);
        client.SendMapInfo(mapSize, mapSize, world.Name, world.BgLightColor, world.BgLightIntensity,
            world.AllowTeleport, world.DayLightIntensity, world.NightLightIntensity);
        client.SendAccountList(0, client.Account.LockList);
        client.SendAccountList(1, client.Account.IgnoreList);
        client.Character = client.Manager.Database.LoadCharacter(client.Account, charId);
        if (client.Character != null) {
            if (client.Character.Dead) {
                client.SendFailure("Character is dead");
                return;
            }

            if (client.Player?.Owner == null)
                client.Player = new Player(client);
            client.SendCreateSuccess(client.Manager.Worlds[world.Id].EnterWorld(client.Player),
                client.Character.CharId);
            client.Manager.Clients[client].WorldInstance = client.Player.Owner.Id;
            client.Manager.Clients[client].WorldName = client.Player.Owner.Name;
        }
        else {
            client.SendFailure("Failed to load character");
        }
    }
}